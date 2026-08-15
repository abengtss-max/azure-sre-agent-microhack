'use strict';

const path = require('path');
const express = require('express');
const { initTelemetry, trackEvent, trackMetric } = require('./lib/telemetry');
const db = require('./lib/db');
const redisLib = require('./lib/redis');

const ROLE = (process.env.ROLE || 'gateway').toLowerCase();
const PORT = parseInt(process.env.PORT || '8080', 10);

initTelemetry(ROLE);

const app = express();
app.use(express.json());

let started = Date.now();
let requestCount = 0;

app.use((req, res, next) => {
  requestCount++;
  next();
});

// ---- Health probes -------------------------------------------------------
app.get('/health/live', (req, res) => {
  res.json({ status: 'alive', role: ROLE, uptimeSec: Math.round((Date.now() - started) / 1000) });
});

app.get('/health/ready', async (req, res) => {
  // Readiness answers "can this pod serve", not "is the database fast". A slow
  // dependency must not eject every replica from the Service - that turns a
  // degradation into an outage and stops the remedy from ever taking effect.
  if (['crew-scheduling', 'booking', 'telemetry-ingest'].includes(ROLE) && db.isConfigured()) {
    try {
      const pool = db.getPool();
      await Promise.race([
        pool.query('SELECT 1'),
        new Promise((resolve) => setTimeout(() => resolve('slow'), 1000))
      ]);
    } catch (err) {
      // Only a hard failure (refused, unresolvable, rejected credentials) means
      // this pod genuinely cannot serve.
      const hard = ['ECONNREFUSED', 'ENOTFOUND', 'EHOSTUNREACH', '28P01', '3D000'];
      if (hard.includes(err.code)) {
        return res.status(503).json({ status: 'not-ready', reason: 'database unreachable' });
      }
    }
  }
  res.json({ status: 'ready', role: ROLE });
});

app.get('/api/health', (req, res) => {
  res.json({ role: ROLE, requests: requestCount });
});

// ---- Role-specific domain endpoints -------------------------------------
function registerRoleRoutes() {
  switch (ROLE) {
    case 'flight-ops':
      app.get('/api/flights', async (req, res) => {
        try {
          const pool = db.getPool();
          const { rows } = pool
            ? await pool.query('SELECT flight_no, origin, destination, status FROM flights ORDER BY id LIMIT 30')
            : { rows: [] };
          res.json({ flights: rows, count: rows.length });
        } catch (err) {
          res.status(500).json({ error: err.message });
        }
      });
      break;

    case 'crew-scheduling':
      app.get('/api/crew', async (req, res) => {
        try {
          const pool = db.getPool();
          const { rows } = await pool.query(
            `SELECT flight_no, crew_member, role, assigned
               FROM crew_roster
              WHERE assigned = true AND role <> 'Cabin Crew'
              ORDER BY flight_no, crew_member
              LIMIT 40`
          );
          res.json({ roster: rows, count: rows.length });
        } catch (err) {
          res.status(500).json({ error: err.message });
        }
      });
      break;

    case 'booking':
      app.post('/api/book', async (req, res) => {
        try {
          const pnr = 'PNR' + Math.random().toString(36).slice(2, 8).toUpperCase();
          const passenger = (req.body && req.body.passenger) || 'Traveler';
          const flightNo = (req.body && req.body.flightNo) || 'AE100';
          const pool = db.getPool();
          if (pool) {
            await pool.query('INSERT INTO bookings (pnr, passenger, flight_no) VALUES ($1,$2,$3)', [
              pnr, passenger, flightNo
            ]);
          }
          const rc = await redisLib.getClient();
          if (rc) await redisLib.cacheSet(`session:${pnr}`, JSON.stringify({ passenger, flightNo }), 900);
          res.json({ pnr, passenger, flightNo, status: 'confirmed' });
        } catch (err) {
          res.status(500).json({ error: err.message });
        }
      });
      app.get('/api/bookings/count', async (req, res) => {
        try {
          // The counter is served from the cache; the reservations table only
          // grows, so it is refreshed from the planner's row estimate rather
          // than scanned on every request.
          const cached = await redisLib.cacheGet('bookings:count');
          if (cached !== null && cached !== undefined) {
            return res.json({ bookings: Number(cached), cached: true });
          }
          const pool = db.getPool();
          if (!pool) return res.json({ bookings: 0 });
          const { rows } = await pool.query(
            "SELECT reltuples::bigint AS c FROM pg_class WHERE relname = 'bookings'"
          );
          let count = rows.length ? Number(rows[0].c) : -1;
          if (count < 0) {
            const exact = await pool.query('SELECT count(*)::int AS c FROM bookings');
            count = exact.rows[0].c;
          }
          await redisLib.cacheSet('bookings:count', String(count), 10);
          res.json({ bookings: count, cached: false });
        } catch (err) {
          res.status(500).json({ error: err.message });
        }
      });
      break;

    case 'baggage':
      app.get('/api/baggage/throughput', async (req, res) => {
        res.json({ bagsPerMinute: 400 + Math.floor(Math.random() * 200), inTransit: Math.floor(Math.random() * 5000) });
      });
      break;

    case 'telemetry-ingest':
      app.post('/api/telemetry', async (req, res) => {
        trackMetric('aircraft_telemetry_events', 1);
        res.json({ accepted: true, ts: Date.now() });
      });
      break;

    case 'gateway':
    default:
      registerGatewayRoutes();
      break;
  }
}

// The gateway serves the Ops Center GUI and aggregates downstream health.
function registerGatewayRoutes() {
  const services = {
    'flight-ops': process.env.SVC_FLIGHT_OPS || 'http://flight-ops',
    'crew-scheduling': process.env.SVC_CREW || 'http://crew-scheduling',
    booking: process.env.SVC_BOOKING || 'http://booking',
    baggage: process.env.SVC_BAGGAGE || 'http://baggage',
    'telemetry-ingest': process.env.SVC_TELEMETRY || 'http://telemetry-ingest'
  };

  const LABELS = {
    'flight-ops': 'Flight Ops',
    'crew-scheduling': 'Crew Scheduling',
    booking: 'Booking & Check-in',
    baggage: 'Baggage',
    'telemetry-ingest': 'Telemetry Ingest'
  };
  // Core revenue-path services raise higher-severity incidents when they fail.
  const CORE = { booking: 'SEV-1', 'flight-ops': 'SEV-1' };

  // Probe each service's REAL user-facing endpoint (not just readiness) so the
  // Ops Center reflects what customers actually experience, not just pod state.
  // This measures genuine request latency and status.
  const PROBES = {
    'flight-ops': { method: 'GET', path: '/api/flights' },
    'crew-scheduling': { method: 'GET', path: '/api/crew' },
    booking: { method: 'GET', path: '/api/bookings/count' },
    baggage: { method: 'GET', path: '/api/baggage/throughput' },
    'telemetry-ingest': { method: 'POST', path: '/api/telemetry' }
  };

  async function probe(url, spec) {
    const start = Date.now();
    try {
      const controller = new AbortController();
      const t = setTimeout(() => controller.abort(), 4000);
      const opts = { method: spec.method, signal: controller.signal };
      if (spec.method === 'POST') {
        opts.headers = { 'content-type': 'application/json' };
        opts.body = '{}';
      }
      const r = await fetch(`${url}${spec.path}`, opts);
      clearTimeout(t);
      return { ok: r.ok, status: r.status, latencyMs: Date.now() - start };
    } catch (err) {
      return { ok: false, status: 0, latencyMs: Date.now() - start, error: err.name };
    }
  }

  // A single probe samples an instantaneous queue depth, so one reading swings
  // wildly on a service that is steadily degraded. Keep a short window per
  // service and report percentiles, the way an operator would read a dashboard.
  const WINDOW = 12;
  const history = {};
  const latest = {};

  function summarise(name) {
    const h = history[name] || [];
    if (!h.length) return null;

    const sorted = h.map((x) => x.latencyMs).sort((a, b) => a - b);
    const at = (q) => sorted[Math.min(sorted.length - 1, Math.max(0, Math.ceil(sorted.length * q) - 1))];
    const failures = h.filter((x) => !x.ok).length;
    const errorRatePct = +((failures / h.length) * 100).toFixed(1);
    const last = h[h.length - 1];

    return {
      // A service is down when it is mostly failing, not because one probe
      // caught it mid-restart.
      ok: errorRatePct < 50,
      status: last.status,
      latencyMs: at(0.95),
      p50Ms: at(0.5),
      p95Ms: at(0.95),
      lastMs: last.latencyMs,
      errorRatePct,
      samples: h.length
    };
  }

  async function sampleAll() {
    await Promise.all(
      Object.entries(services).map(async ([name, url]) => {
        const result = await probe(url, PROBES[name]);
        const h = history[name] || (history[name] = []);
        h.push(result);
        if (h.length > WINDOW) h.shift();
        latest[name] = result;
      })
    );
  }

  // Poll continuously so the board reflects the platform's recent behaviour
  // rather than whatever a single request happened to catch.
  setInterval(() => {
    sampleAll().catch(() => {});
  }, 5000).unref();

  // Derive executive/business/operational signals from the REAL probe results so
  // every panel reflects the live state of the platform.
  function deriveSignals(health) {
    const values = Object.values(health);
    const total = values.length || 1;
    const down = values.filter((h) => !h.ok).length;
    // Aetherion's latency budget for a passenger-facing path is 400ms.
    const slow = values.filter((h) => h.ok && h.p95Ms > 400).length;
    const flaky = values.filter((h) => h.ok && h.errorRatePct > 0).length;

    const score = Math.min(100, down * 32 + slow * 20 + flaky * 12 + (down + slow + flaky ? 6 : 4));
    const level = score >= 60 ? 'HIGH' : score >= 25 ? 'MEDIUM' : 'LOW';

    const latencies = values.map((h) => h.p95Ms || 0).sort((a, b) => a - b);
    const p95Ms = latencies.length ? latencies[Math.min(latencies.length - 1, Math.ceil(latencies.length * 0.95) - 1)] : 0;
    const errorRatePct = +((down / total) * 100).toFixed(2);
    const availabilityPct = +Math.max(0, 100 - down * 0.7 - slow * 0.15).toFixed(2);
    const requestsPerMin = Math.max(0, Math.round(52000 * (1 - down * 0.12 - slow * 0.04)));

    const incidents = [];
    for (const [name, h] of Object.entries(health)) {
      const label = LABELS[name] || name;
      if (!h.ok) {
        incidents.push({ sev: CORE[name] || 'SEV-2', title: `${label} unavailable`, status: 'Investigating', service: name });
      } else if (h.errorRatePct > 0) {
        incidents.push({ sev: 'SEV-3', title: `${label} intermittent errors`, status: 'Investigating', service: name });
      } else if (h.p95Ms > 400) {
        incidents.push({ sev: 'SEV-3', title: `${label} elevated latency`, status: 'Monitoring', service: name });
      }
    }

    const impact = {
      revenue: down * 920000 + slow * 140000,
      passengers: down * 8600 + slow * 1400,
      flightsDelayed: down * 24 + slow * 6
    };

    const ribbon = {
      flightsActive: 1247,
      passengersInTransit: 182331,
      airports: 25,
      aircraftTracked: 873,
      incidents: incidents.length,
      slaPct: availabilityPct
    };

    return {
      risk: { score, level },
      metrics: { p95Ms, errorRatePct, availabilityPct, requestsPerMin },
      impact,
      ribbon,
      incidents
    };
  }

  app.get('/api/status', async (req, res) => {
    if (!Object.keys(history).length) await sampleAll();
    const health = {};
    for (const name of Object.keys(services)) {
      health[name] = summarise(name) || { ok: false, status: 0, latencyMs: 0, p50Ms: 0, p95Ms: 0, errorRatePct: 100, samples: 0 };
    }
    const healthy = Object.values(health).every((h) => h.ok);
    const derived = deriveSignals(health);
    trackEvent('ops_status_poll', { healthy: String(healthy), risk: derived.risk.level });
    res.json({
      platform: 'Aetherion AirOps',
      overall: healthy ? 'operational' : 'degraded',
      services: health,
      ...derived,
      generatedAt: new Date().toISOString()
    });
  });


  // Reverse-proxy the downstream domain endpoints so external traffic (the k6
  // load generator via APIM, and operators hitting the gateway directly) reaches
  // the role services. Without this the gateway 404s these paths and the load
  // never exercises the downstream services, so degradations produce no
  // signal under load.
  const PROXY_ROUTES = [
    { method: 'get', path: '/api/flights', target: services['flight-ops'] },
    { method: 'get', path: '/api/crew', target: services['crew-scheduling'] },
    { method: 'post', path: '/api/book', target: services.booking },
    { method: 'get', path: '/api/bookings/count', target: services.booking },
    { method: 'get', path: '/api/baggage/throughput', target: services.baggage },
    { method: 'post', path: '/api/telemetry', target: services['telemetry-ingest'] }
  ];
  for (const route of PROXY_ROUTES) {
    app[route.method](route.path, async (req, res) => {
      const start = Date.now();
      try {
        const controller = new AbortController();
        const t = setTimeout(() => controller.abort(), 6000);
        const opts = { method: req.method, signal: controller.signal, headers: { 'content-type': 'application/json' } };
        if (req.method === 'POST') opts.body = JSON.stringify(req.body || {});
        const r = await fetch(`${route.target}${req.path}`, opts);
        clearTimeout(t);
        const body = await r.text();
        const ct = r.headers.get('content-type');
        if (ct) res.set('content-type', ct);
        res.status(r.status).send(body);
      } catch (err) {
        res.status(502).json({ error: 'upstream_unreachable', service: route.path, detail: err.name, latencyMs: Date.now() - start });
      }
    });
  }

  // Serve the Ops Center single-page GUI
  const webDir = path.join(__dirname, '..', 'web');
  app.use('/', express.static(webDir));
  app.get('/', (req, res) => res.sendFile(path.join(webDir, 'index.html')));
}

async function bootstrap() {
  try {
    if (['flight-ops', 'crew-scheduling', 'booking', 'telemetry-ingest'].includes(ROLE)) {
      await db.initSchema();
    }
  } catch (err) {
    console.error('[bootstrap] schema init failed (continuing):', err.message);
  }
  registerRoleRoutes();
  app.listen(PORT, () => {
    console.log(`[aetherion] role=${ROLE} listening on :${PORT}`);
  });
}

bootstrap();
