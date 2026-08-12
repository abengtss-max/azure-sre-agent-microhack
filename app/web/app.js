'use strict';

const SERVICE_LABELS = {
  'flight-ops': 'Flight Ops',
  'crew-scheduling': 'Crew Scheduling',
  booking: 'Booking & Check-in',
  baggage: 'Baggage',
  'telemetry-ingest': 'Telemetry Ingest'
};

const feedEl = document.getElementById('feed');
const MAX_FEED = 40;
let lastState = {};
let flightOpsDown = false;

function pushFeed(text, level = 'info') {
  const li = document.createElement('li');
  if (level !== 'info') li.classList.add(level);
  const now = new Date().toLocaleTimeString();
  li.innerHTML = `<span class="time">${now}</span><span>${text}</span>`;
  feedEl.prepend(li);
  while (feedEl.children.length > MAX_FEED) feedEl.removeChild(feedEl.lastChild);
}

function classify(h) {
  if (!h) return 'muted';
  if (!h.ok) return 'red';
  if (h.latencyMs > 1500) return 'amber';
  return 'green';
}

function fmt(n) {
  return (n || 0).toLocaleString('en-US');
}
function fmtMoney(n) {
  if (!n) return '$0';
  if (n >= 1000000) return '$' + (n / 1000000).toFixed(1) + 'M';
  if (n >= 1000) return '$' + (n / 1000).toFixed(0) + 'K';
  return '$' + n;
}

function renderTiles(services) {
  const tiles = document.getElementById('tiles');
  tiles.innerHTML = '';
  for (const [name, h] of Object.entries(services)) {
    const cls = classify(h);
    const label = SERVICE_LABELS[name] || name;
    const state = h.ok ? (cls === 'amber' ? 'Degraded' : 'Healthy') : 'DOWN';
    const div = document.createElement('div');
    div.className = `tile ${cls}`;
    div.innerHTML = `
      <h3>${label}</h3>
      <div class="state">${state}</div>
      <div class="meta">${h.ok ? `${h.latencyMs} ms` : `HTTP ${h.status || 'timeout'}`}</div>`;
    tiles.appendChild(div);

    // Emit feed events when a service changes state
    const prev = lastState[name];
    if (prev !== undefined && prev !== cls) {
      if (cls === 'red') pushFeed(`${label} went DOWN`, 'err');
      else if (cls === 'amber') pushFeed(`${label} degraded (high latency)`, 'warn');
      else if (cls === 'green') pushFeed(`${label} recovered`, 'info');
    }
    lastState[name] = cls;
  }
}

function renderHealthTable(services) {
  const rows = document.getElementById('healthRows');
  rows.innerHTML = '';
  for (const [name, h] of Object.entries(services)) {
    const cls = classify(h);
    const label = SERVICE_LABELS[name] || name;
    const state = h.ok ? (cls === 'amber' ? 'Degraded' : 'Healthy') : 'DOWN';
    const badge = cls === 'green' ? 'ontime' : cls === 'amber' ? 'delayed' : 'cancelled';
    const tr = document.createElement('tr');
    tr.innerHTML = `<td>${label}</td><td><span class="badge ${badge}">${state}</span></td>` +
      `<td>${h.ok ? h.latencyMs + ' ms' : '—'}</td>`;
    rows.appendChild(tr);
  }
}

function renderRibbon(rb) {
  if (!rb) return;
  document.getElementById('rbFlights').textContent = fmt(rb.flightsActive);
  document.getElementById('rbPax').textContent = fmt(rb.passengersInTransit);
  document.getElementById('rbAirports').textContent = fmt(rb.airports);
  document.getElementById('rbAircraft').textContent = fmt(rb.aircraftTracked);
  const inc = document.getElementById('rbIncidents');
  inc.textContent = fmt(rb.incidents);
  inc.classList.toggle('bad', rb.incidents > 0);
  document.getElementById('rbSla').textContent = (rb.slaPct != null ? rb.slaPct.toFixed(2) : '—') + '%';
}

function renderRisk(risk) {
  if (!risk) return;
  const panel = document.getElementById('riskPanel');
  const lvl = document.getElementById('riskLevel');
  lvl.textContent = risk.level;
  document.getElementById('riskScore').textContent = risk.score;
  const cls = risk.level === 'HIGH' ? 'red' : risk.level === 'MEDIUM' ? 'amber' : 'green';
  panel.className = `panel risk ${cls}`;
  lvl.className = `risk-level ${cls}`;
  const fill = document.getElementById('gaugeFill');
  fill.style.width = Math.min(100, risk.score) + '%';
  fill.className = `gauge-fill ${cls}`;
}

function renderMetrics(m) {
  if (!m) return;
  document.getElementById('mP95').textContent = (m.p95Ms || 0) + ' ms';
  const err = document.getElementById('mErr');
  err.textContent = (m.errorRatePct != null ? m.errorRatePct.toFixed(2) : '0') + '%';
  err.classList.toggle('bad', m.errorRatePct > 0);
  document.getElementById('mRpm').textContent = fmt(m.requestsPerMin);
  document.getElementById('mAvail').textContent = (m.availabilityPct != null ? m.availabilityPct.toFixed(2) : '—') + '%';
}

let prevImpact = null;
function flashImpact(el, recover) {
  const cell = el.parentElement;
  if (!cell || typeof cell.animate !== 'function') return;
  cell.animate(
    [
      { backgroundColor: recover ? 'rgba(46,204,113,0.35)' : 'rgba(231,76,60,0.30)' },
      { backgroundColor: 'transparent' }
    ],
    { duration: 900, easing: 'ease-out' }
  );
}

function renderImpact(imp) {
  if (!imp) return;
  const rev = document.getElementById('impRevenue');
  const pax = document.getElementById('impPax');
  const fl = document.getElementById('impFlights');
  rev.textContent = fmtMoney(imp.revenue);
  rev.classList.toggle('bad', imp.revenue > 0);
  pax.textContent = fmt(imp.passengers);
  pax.classList.toggle('bad', imp.passengers > 0);
  fl.textContent = fmt(imp.flightsDelayed);
  fl.classList.toggle('bad', imp.flightsDelayed > 0);
  if (prevImpact) {
    if (imp.revenue !== prevImpact.revenue) flashImpact(rev, imp.revenue < prevImpact.revenue);
    if (imp.passengers !== prevImpact.passengers) flashImpact(pax, imp.passengers < prevImpact.passengers);
    if (imp.flightsDelayed !== prevImpact.flightsDelayed) flashImpact(fl, imp.flightsDelayed < prevImpact.flightsDelayed);
  }
  prevImpact = { revenue: imp.revenue, passengers: imp.passengers, flightsDelayed: imp.flightsDelayed };
}

function renderIncidents(incidents) {
  const el = document.getElementById('incidents');
  el.innerHTML = '';
  if (!incidents || incidents.length === 0) {
    el.innerHTML = '<li class="muted">No active incidents.</li>';
    return;
  }
  for (const inc of incidents) {
    const sevCls = inc.sev === 'SEV-1' ? 'red' : inc.sev === 'SEV-2' ? 'amber' : 'info';
    const rowCls = inc.sev === 'SEV-1' ? 'sev1' : inc.sev === 'SEV-2' ? 'sev2' : 'sev3';
    const li = document.createElement('li');
    li.className = 'incident ' + rowCls;
    li.innerHTML = `<span class="sev ${sevCls}">${inc.sev}</span>` +
      `<span class="inc-title">${inc.title}</span>` +
      `<span class="inc-status">${inc.status}</span>`;
    el.appendChild(li);
  }
}

function setOverall(overall) {
  const dot = document.getElementById('overallDot');
  const text = document.getElementById('overallText');
  if (overall === 'operational') {
    dot.className = 'dot green';
    text.textContent = 'All Systems Operational';
  } else {
    dot.className = 'dot red';
    text.textContent = 'Service Degradation Detected';
  }
}

// ---- Global operations map ------------------------------------------------
const SVG_NS = 'http://www.w3.org/2000/svg';
// Approximate airport positions on the 1000x440 equirectangular viewBox
// (x = (lon+180)/360*1000, y = (90-lat)/180*440).
const AIRPORTS = {
  LAX: { x: 171, y: 137 }, SFO: { x: 160, y: 128 }, ORD: { x: 256, y: 117 },
  JFK: { x: 295, y: 121 }, GRU: { x: 371, y: 277 }, LHR: { x: 494, y: 94 },
  CDG: { x: 512, y: 100 }, FRA: { x: 524, y: 98 }, DXB: { x: 654, y: 158 },
  BOM: { x: 702, y: 173 }, SIN: { x: 789, y: 217 }, HKG: { x: 816, y: 165 },
  HND: { x: 888, y: 133 }, SYD: { x: 920, y: 303 }
};
// Airports that anchor a monitored service corridor (labelled prominently).
const MAJOR = new Set(['LHR', 'JFK', 'FRA', 'DXB', 'SIN', 'HND', 'LAX', 'CDG']);
// Each service owns a route so a specific outage lights up a specific corridor.
const SERVICE_ROUTES = [
  { service: 'flight-ops', a: 'LHR', b: 'JFK' },
  { service: 'crew-scheduling', a: 'FRA', b: 'DXB' },
  { service: 'booking', a: 'SIN', b: 'HND' },
  { service: 'baggage', a: 'LAX', b: 'CDG' },
  { service: 'telemetry-ingest', a: 'DXB', b: 'SIN' }
];
const AMBIENT_COUNT = 40;

function curvePath(a, b) {
  const p = AIRPORTS[a], q = AIRPORTS[b];
  const mx = (p.x + q.x) / 2;
  const my = (p.y + q.y) / 2 - Math.abs(q.x - p.x) * 0.16 - 16;
  return `M ${p.x} ${p.y} Q ${mx} ${my} ${q.x} ${q.y}`;
}

function addPlane(svg, d, cls, r, dur) {
  const plane = document.createElementNS(SVG_NS, 'circle');
  plane.setAttribute('r', r);
  plane.setAttribute('class', cls);
  const motion = document.createElementNS(SVG_NS, 'animateMotion');
  motion.setAttribute('dur', dur.toFixed(1) + 's');
  motion.setAttribute('repeatCount', 'indefinite');
  motion.setAttribute('begin', '-' + (Math.random() * dur).toFixed(1) + 's');
  motion.setAttribute('path', d);
  plane.appendChild(motion);
  return { plane, motion };
}

function buildMap() {
  const svg = document.getElementById('map');
  svg.innerHTML = '';

  // faint graticule
  const grid = document.createElementNS(SVG_NS, 'g');
  grid.setAttribute('class', 'graticule');
  for (let x = 0; x <= 1000; x += 100) {
    const l = document.createElementNS(SVG_NS, 'line');
    l.setAttribute('x1', x); l.setAttribute('y1', 0); l.setAttribute('x2', x); l.setAttribute('y2', 440);
    grid.appendChild(l);
  }
  for (let y = 0; y <= 440; y += 80) {
    const l = document.createElementNS(SVG_NS, 'line');
    l.setAttribute('x1', 0); l.setAttribute('y1', y); l.setAttribute('x2', 1000); l.setAttribute('y2', y);
    grid.appendChild(l);
  }
  svg.appendChild(grid);

  // ambient traffic (decorative) — many flights so the map feels busy
  const codes = Object.keys(AIRPORTS);
  for (let i = 0; i < AMBIENT_COUNT; i++) {
    const a = codes[Math.floor(Math.random() * codes.length)];
    let b = codes[Math.floor(Math.random() * codes.length)];
    while (b === a) b = codes[Math.floor(Math.random() * codes.length)];
    const d = curvePath(a, b);
    const path = document.createElementNS(SVG_NS, 'path');
    path.setAttribute('d', d);
    path.setAttribute('class', 'route ambient');
    svg.appendChild(path);
    const { plane } = addPlane(svg, d, 'plane ambient', 2, 7 + Math.random() * 7);
    svg.appendChild(plane);
  }

  // monitored service corridors (bright, health-driven)
  for (const r of SERVICE_ROUTES) {
    const d = curvePath(r.a, r.b);
    const path = document.createElementNS(SVG_NS, 'path');
    path.setAttribute('d', d);
    path.setAttribute('class', 'route green');
    path.dataset.service = r.service;
    svg.appendChild(path);
    const { plane } = addPlane(svg, d, 'plane', 3.4, 5 + Math.random() * 3);
    plane.dataset.service = r.service;
    svg.appendChild(plane);
  }

  // airport nodes
  for (const [code, pos] of Object.entries(AIRPORTS)) {
    const major = MAJOR.has(code);
    const g = document.createElementNS(SVG_NS, 'g');
    g.setAttribute('class', 'airport' + (major ? '' : ' minor'));
    g.dataset.code = code;
    const c = document.createElementNS(SVG_NS, 'circle');
    c.setAttribute('cx', pos.x); c.setAttribute('cy', pos.y); c.setAttribute('r', major ? 5 : 3.5);
    c.setAttribute('class', 'node ' + (major ? 'green' : 'ambient'));
    const t = document.createElementNS(SVG_NS, 'text');
    t.setAttribute('x', pos.x); t.setAttribute('y', pos.y - 9);
    t.setAttribute('class', 'code');
    t.textContent = code;
    g.appendChild(c); g.appendChild(t);
    svg.appendChild(g);
  }
}

function updateMap(services) {
  const svg = document.getElementById('map');
  if (!svg || !svg.childNodes.length) return;
  const worst = {}; // airport code -> worst class among its service corridors
  const rank = { green: 0, amber: 1, red: 2, muted: 1 };
  for (const r of SERVICE_ROUTES) {
    const cls = classify(services[r.service]);
    svg.querySelectorAll(`path.route[data-service="${r.service}"]`).forEach((p) => {
      p.setAttribute('class', `route ${cls}`);
    });
    svg.querySelectorAll(`circle.plane[data-service="${r.service}"]`).forEach((p) => {
      p.setAttribute('class', `plane ${cls}`);
    });
    for (const code of [r.a, r.b]) {
      if (worst[code] === undefined || rank[cls] > rank[worst[code]]) worst[code] = cls;
    }
  }
  svg.querySelectorAll('g.airport').forEach((g) => {
    if (worst[g.dataset.code] === undefined) return; // leave ambient airports as-is
    const cls = worst[g.dataset.code];
    g.querySelector('circle.node').setAttribute('class', `node ${cls}`);
  });
}

async function pollStatus() {
  try {
    const r = await fetch('/api/status', { cache: 'no-store' });
    if (!r.ok) throw new Error('HTTP ' + r.status);
    const data = await r.json();
    setOverall(data.overall);
    renderTiles(data.services);
    renderHealthTable(data.services);
    renderRibbon(data.ribbon);
    renderRisk(data.risk);
    renderMetrics(data.metrics);
    renderImpact(data.impact);
    renderIncidents(data.incidents);
    updateMap(data.services);
    flightOpsDown = classify(data.services['flight-ops']) === 'red';
    renderFlightBoard();
  } catch (err) {
    setOverall('degraded');
    document.getElementById('overallText').textContent = 'Gateway unreachable';
    pushFeed('Ops Center could not reach the gateway', 'err');
  }
}

const STATUS_LABELS = ['On Time', 'On Time', 'On Time', 'Delayed', 'Boarding'];
function renderFlightBoard() {
  const board = document.getElementById('flightBoard');
  const rows = document.getElementById('flightRows');
  rows.innerHTML = '';
  // Flight Ops feeds the board; if it's unavailable, the board loses its signal.
  if (flightOpsDown) {
    board.classList.add('dark');
    for (let i = 0; i < 8; i++) {
      const tr = document.createElement('tr');
      tr.innerHTML = `<td>AE${100 + i}</td><td>—</td><td>—</td><td><span class="badge cancelled">NO SIGNAL</span></td>`;
      rows.appendChild(tr);
    }
    return;
  }
  board.classList.remove('dark');
  const airports = ['LHR', 'JFK', 'DXB', 'SIN', 'FRA', 'HND', 'LAX', 'CDG'];
  for (let i = 0; i < 8; i++) {
    const o = airports[Math.floor(Math.random() * airports.length)];
    let d = airports[Math.floor(Math.random() * airports.length)];
    while (d === o) d = airports[Math.floor(Math.random() * airports.length)];
    const status = STATUS_LABELS[Math.floor(Math.random() * STATUS_LABELS.length)];
    const badge = status === 'On Time' ? 'ontime' : status === 'Delayed' ? 'delayed' : 'ontime';
    const tr = document.createElement('tr');
    tr.innerHTML = `<td>AE${100 + i}</td><td>${o}</td><td>${d}</td><td><span class="badge ${badge}">${status}</span></td>`;
    rows.appendChild(tr);
  }
}

function tickClock() {
  document.getElementById('clock').textContent = new Date().toLocaleTimeString();
}

pushFeed('Operations Center initialized');
buildMap();
tickClock();
pollStatus();
renderFlightBoard();
setInterval(tickClock, 1000);
setInterval(pollStatus, 2000);
setInterval(renderFlightBoard, 8000);
