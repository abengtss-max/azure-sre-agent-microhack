'use strict';

const redis = require('redis');

let client = null;
let connecting = null;

function isConfigured() {
  return Boolean(process.env.REDIS_HOST);
}

async function getClient() {
  if (!isConfigured()) return null;
  if (client && client.isOpen) return client;
  if (connecting) return connecting;

  const useTls = process.env.REDIS_TLS !== 'false';
  const url = `${useTls ? 'rediss' : 'redis'}://${process.env.REDIS_HOST}:${
    process.env.REDIS_PORT || (useTls ? '6380' : '6379')
  }`;

  client = redis.createClient({
    url,
    password: process.env.REDIS_PASSWORD || undefined,
    socket: { connectTimeout: 5000, reconnectStrategy: (r) => Math.min(r * 200, 2000) }
  });
  client.on('error', (err) => console.error('[redis] error', err.message));

  connecting = client
    .connect()
    .then(() => {
      console.log('[redis] connected');
      connecting = null;
      return client;
    })
    .catch((err) => {
      console.error('[redis] connect failed', err.message);
      connecting = null;
      return null;
    });
  return connecting;
}

module.exports = { getClient, isConfigured };
