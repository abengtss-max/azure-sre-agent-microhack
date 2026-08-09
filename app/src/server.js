'use strict';

const path = require('path');
const express = require('express');
const { initTelemetry, trackEvent, trackMetric } = require('./lib/telemetry');
const db = require('./lib/db');
const redisLib = require('./lib/redis');

const ROLE = (process.env.ROLE || 'gateway').toLowerCase();
const PORT = parseInt(process.env.PORT || '8080', 10);

// Fault injection is controlled entirely by environment variables so a
// facilitator can toggle behaviour with `kubectl set env deploy/<svc> ...`.
//   FAULT_MODE = none | latency | error | crash | memory | db-pool
const FAULT_MODE = (process.env.FAULT_MODE || 'none').toLowerCase();
const FAULT_LATENCY_MS = parseInt(process.env.FAULT_LATENCY_MS || '2500', 10);
const FAULT_ERROR_RATE = parseFloat(process.env.FAULT_ERROR_RATE || '0.5');

initTelemetry(ROLE);

const app = express();
app.use(express.json());

// Simulated memory leak store (only grows when FAULT_MODE=memory)
const leakedMemory = [];
// Leaked DB clients (only grows when FAULT_MODE=db-pool) - never released
const leakedDbClients = [];
let started = Date.now();
let requestCount = 0;

function sleep(ms) {
  return new Promise((r) => setTimeout(r, ms));
}

// Applies the active fault to a domain request. Returns true if the request
// was already handled (e.g. error response) and the caller should stop.
async function applyFault(req, res) {
  requestCount++;
  switch (FAULT_MODE) {
    case 'latency':
      await sleep(FAULT_LATENCY_MS);
      return false;
    case 'error':
      if (Math.random() < FAULT_ERROR_RATE) {
        res.status(500).json({ error: 'Internal error (injected fault)', role: ROLE });
        return true;
      }
      return false;
    case 'memory':
      // Allocate ~5MB per request and hold onto it
      leakedMemory.push(Buffer.alloc(5 * 1024 * 1024, 1));
      return false;
    case 'db-pool': {
      // Leak a pooled connection each request until the pool is exhausted,
      // after which connection acquisition times out and requests fail.
      const pool = db.getPool();
      if (pool) {
        try {
          const client = await pool.connect(); // intentionally never released
          leakedDbClients.push(client);
        } catch (err) {
          res.status(503).json({ error: 'Database connection pool exhausted', role: ROLE });
          return true;
        }
      }
      return false;
    }
    default:
      return false;
  }
}

// ---- Health probes -------------------------------------------------------
app.get('/health/live', (req, res) => {
  // crash fault: liveness fails so Kubernetes restarts the pod -> CrashLoopBackOff
  if (FAULT_MODE === 'crash') {
    return res.status(500).json({ status: 'unhealthy', reason: 'injected crash fault' });
  }
  res.json({ status: 'alive', role: ROLE, uptimeSec: Math.round((Date.now() - started) / 1000) });
});

app.get('/health/ready', async (req, res) => {
  if (FAULT_MODE === 'crash') {
    return res.status(503).json({ status: 'not-ready', reason: 'injected crash fault' });
  }
  // crew-scheduling/booking/telemetry depend on the database
  if (['crew-scheduling', 'booking', 'telemetry-ingest'].includes(ROLE) && db.isConfigured()) {
    try {
      const pool = db.getPool();
      await pool.query('SELECT 1');
    } catch (err) {
      return res.status(503).json({ status: 'not-ready', reason: 'database unreachable' });
    }
  }
  res.json({ status: 'ready', role: ROLE });
});

app.get('/api/health', (req, res) => {
  res.json({ role: ROLE, faultMode: FAULT_MODE, requests: requestCount });
});

// ---- Role-specific domain endpoints -------------------------------------
function registerRoleRoutes() {
  switch (ROLE) {
    case 'flight-ops':
      app.get('/api/flights', async (req, res) => {
        if (await applyFault(req, res)) return;
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
        if (await applyFault(req, res)) return;
        try {
          const pool = db.getPool();
          const { rows } = await pool.query(
            'SELECT flight_no, crew_member, role, assigned FROM crew_roster ORDER BY id LIMIT 40'
          );
          res.json({ roster: rows, count: rows.length });
        } catch (err) {
          res.status(500).json({ error: err.message });
        }
      });
      break;

    case 'booking':
      app.post('/api/book', async (req, res) => {
        if (await applyFault(req, res)) return;
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
          if (rc) await rc.set(`session:${pnr}`, JSON.stringify({ passenger, flightNo }), { EX: 900 });
          res.json({ pnr, passenger, flightNo, status: 'confirmed' });
        } catch (err) {
          res.status(500).json({ error: err.message });
        }
      });
      app.get('/api/bookings/count', async (req, res) => {
        if (await applyFault(req, res)) return;
        try {
          const pool = db.getPool();
          const { rows } = pool ? await pool.query('SELECT count(*)::int AS c FROM bookings') : { rows: [{ c: 0 }] };
          res.json({ bookings: rows[0].c });
        } catch (err) {
          res.status(500).json({ error: err.message });
        }
      });
      break;

    case 'baggage':
      app.get('/api/baggage/throughput', async (req, res) => {
        if (await applyFault(req, res)) return;
        res.json({ bagsPerMinute: 400 + Math.floor(Math.random() * 200), inTransit: Math.floor(Math.random() * 5000) });
      });
      break;

    case 'telemetry-ingest':
      app.post('/api/telemetry', async (req, res) => {
        if (await applyFault(req, res)) return;
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
  // Ops Center reacts authentically to injected latency/error faults instead of
  // only to pod crashes. This measures genuine request latency and status.
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

  // Derive executive/business/operational signals from the REAL probe results so
  // every panel reacts authentically the moment a fault is injected.
  function deriveSignals(health) {
    const values = Object.values(health);
    const total = values.length || 1;
    const down = values.filter((h) => !h.ok).length;
    const slow = values.filter((h) => h.ok && h.latencyMs > 1500).length;

    const score = Math.min(100, down * 32 + slow * 14 + (down + slow ? 6 : 4));
    const level = score >= 60 ? 'HIGH' : score >= 25 ? 'MEDIUM' : 'LOW';

    const latencies = values.map((h) => h.latencyMs || 0).sort((a, b) => a - b);
    const p95Ms = latencies.length ? latencies[Math.min(latencies.length - 1, Math.ceil(latencies.length * 0.95) - 1)] : 0;
    const errorRatePct = +((down / total) * 100).toFixed(2);
    const availabilityPct = +Math.max(0, 100 - down * 0.7 - slow * 0.15).toFixed(2);
    const requestsPerMin = Math.max(0, Math.round(52000 * (1 - down * 0.12 - slow * 0.04)));

    const incidents = [];
    for (const [name, h] of Object.entries(health)) {
      const label = LABELS[name] || name;
      if (!h.ok) {
        incidents.push({ sev: CORE[name] || 'SEV-2', title: `${label} unavailable`, status: 'Investigating', service: name });
      } else if (h.latencyMs > 1500) {
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
    if (await applyFault(req, res)) return;
    const entries = await Promise.all(
      Object.entries(services).map(async ([name, url]) => [name, await probe(url, PROBES[name])])
    );
    const health = Object.fromEntries(entries);
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
  // never exercises the downstream services, so injected faults produce no
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
    console.log(`[aetherion] role=${ROLE} listening on :${PORT} faultMode=${FAULT_MODE}`);
  });
}

bootstrap();
