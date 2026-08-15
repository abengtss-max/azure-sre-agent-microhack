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

// Callers must not hang on the cache. A read that exceeds this budget is treated
// as a miss and served from the source of truth instead.
const CACHE_TIMEOUT_MS = parseInt(process.env.REDIS_TIMEOUT_MS || '1500', 10);

function withTimeout(promise) {
  return Promise.race([
    promise,
    new Promise((resolve) => setTimeout(() => resolve(null), CACHE_TIMEOUT_MS))
  ]).catch(() => null);
}

async function cacheGet(key) {
  return withTimeout(
    (async () => {
      const c = await getClient();
      if (!c) return null;
      return c.get(key);
    })()
  );
}

async function cacheSet(key, value, ttlSeconds) {
  return withTimeout(
    (async () => {
      const c = await getClient();
      if (!c) return null;
      return c.set(key, value, { EX: ttlSeconds });
    })()
  );
}

module.exports = { getClient, isConfigured, cacheGet, cacheSet, CACHE_TIMEOUT_MS };
