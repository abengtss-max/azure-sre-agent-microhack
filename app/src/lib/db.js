'use strict';

const { Pool } = require('pg');

// A small connection pool. The pool max is deliberately small so the
// "db-pool" fault (leaking connections) exhausts it quickly and visibly.
const POOL_MAX = parseInt(process.env.PG_POOL_MAX || '5', 10);

let pool = null;

function isConfigured() {
  return Boolean(process.env.PGHOST);
}

function getPool() {
  if (!isConfigured()) return null;
  if (!pool) {
    pool = new Pool({
      host: process.env.PGHOST,
      port: parseInt(process.env.PGPORT || '5432', 10),
      user: process.env.PGUSER,
      password: process.env.PGPASSWORD,
      database: process.env.PGDATABASE || 'aetherion',
      max: POOL_MAX,
      idleTimeoutMillis: 30000,
      connectionTimeoutMillis: 5000,
      ssl: process.env.PGSSL === 'disable' ? false : { rejectUnauthorized: false }
    });
    pool.on('error', (err) => console.error('[db] idle client error', err.message));
  }
  return pool;
}

// Idempotent schema + seed data so every service can start cleanly.
async function initSchema() {
  const p = getPool();
  if (!p) {
    console.log('[db] PGHOST not set - database features disabled');
    return;
  }
  const client = await p.connect();
  try {
    await client.query(`
      CREATE TABLE IF NOT EXISTS flights (
        id SERIAL PRIMARY KEY,
        flight_no TEXT NOT NULL,
        origin TEXT NOT NULL,
        destination TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'On Time',
        scheduled TIMESTAMPTZ NOT NULL DEFAULT now()
      );
      CREATE TABLE IF NOT EXISTS crew_roster (
        id SERIAL PRIMARY KEY,
        flight_no TEXT NOT NULL,
        crew_member TEXT NOT NULL,
        role TEXT NOT NULL,
        assigned BOOLEAN NOT NULL DEFAULT true
      );
      CREATE TABLE IF NOT EXISTS bookings (
        id SERIAL PRIMARY KEY,
        pnr TEXT NOT NULL,
        passenger TEXT NOT NULL,
        flight_no TEXT NOT NULL,
        created_at TIMESTAMPTZ NOT NULL DEFAULT now()
      );
    `);

    const { rows } = await client.query('SELECT count(*)::int AS c FROM flights');
    if (rows[0].c === 0) {
      const airports = ['LHR', 'JFK', 'DXB', 'SIN', 'FRA', 'HND', 'LAX', 'CDG', 'AMS', 'SYD'];
      for (let i = 0; i < 30; i++) {
        const o = airports[Math.floor(Math.random() * airports.length)];
        let d = airports[Math.floor(Math.random() * airports.length)];
        while (d === o) d = airports[Math.floor(Math.random() * airports.length)];
        const flightNo = `AE${100 + i}`;
        await client.query(
          'INSERT INTO flights (flight_no, origin, destination, status) VALUES ($1,$2,$3,$4)',
          [flightNo, o, d, 'On Time']
        );
        await client.query(
          'INSERT INTO crew_roster (flight_no, crew_member, role) VALUES ($1,$2,$3),($1,$4,$5)',
          [flightNo, `Capt. ${o}${i}`, 'Captain', `FO ${d}${i}`, 'First Officer']
        );
      }
      console.log('[db] seeded flights and crew_roster');
    }
  } finally {
    client.release();
  }
}

module.exports = { getPool, initSchema, isConfigured, POOL_MAX };
