import http from 'k6/http';
import { check, sleep, group } from 'k6';
import { Rate } from 'k6/metrics';

// Aetherion AirOps traffic generator.
// Drives realistic mixed operational journeys so metrics/logs stay populated and
// degradations produce visible signal.
//
// Configure via environment variables:
//   BASE_URL    - APIM gateway base URL (required), e.g. https://<apim>.azure-api.net/aetherion
//   DIRECT_URL  - platform gateway base URL, used by first-party station traffic
//                 that does not transit the partner front door
//   MODE        - "normal" (default), "surge", "crew-burst", or "major"
//   VUS         - override virtual users
//   API_KEY     - APIM subscription key (optional; sent as Ocp-Apim-Subscription-Key)

const BASE_URL = (__ENV.BASE_URL || 'http://localhost:8080').replace(/\/$/, '');
const DIRECT_URL = (__ENV.DIRECT_URL || '').replace(/\/$/, '');
const MODE = __ENV.MODE || 'normal';
const API_KEY = __ENV.API_KEY || '';

const normalVus = parseInt(__ENV.VUS || '25', 10);
const surgeVus = parseInt(__ENV.VUS || '120', 10);
const burstVus = parseInt(__ENV.VUS || '250', 10);
const majorVus = parseInt(__ENV.VUS || '200', 10);

// Station and mobile-backend traffic reaches the platform directly rather than
// through the partner front door, so a fault at the edge does not silence the
// services behind it.
const internalVus = parseInt(__ENV.INTERNAL_VUS || '12', 10);
// Crew sign-on is a separate client population from check-in. Keeping it in its
// own stream means a slow roster lookup cannot starve the check-in path of
// traffic, which is what would happen if both shared one journey loop.
const crewVus = parseInt(__ENV.CREW_VUS || '0', 10);
// Check-in desks and kiosks are their own population too.
const checkInVus = parseInt(__ENV.CHECKIN_VUS || '0', 10);

function scenario(name, vus, exec) {
  const s = { executor: 'constant-vus', vus, duration: __ENV.DURATION || '24h' };
  if (exec) s.exec = exec;
  return { [name]: s };
}

function partnerScenario() {
  if (MODE === 'crew-burst') return scenario('crewBurst', burstVus, 'partnerTraffic');
  // Peak departure wave: the whole platform is busy and rosters are pulled
  // repeatedly as crews sign on.
  if (MODE === 'major') return scenario('major', majorVus, 'partnerTraffic');
  // A departure-wave surge holds a sustained, closed-loop concurrency. Ramping
  // stages made the offered load vary while an incident was open, so the same
  // fault produced a different symptom minute to minute.
  if (MODE === 'surge') return scenario('surge', surgeVus, 'partnerTraffic');
  return scenario('steady', normalVus, 'partnerTraffic');
}

export const options = {
  scenarios: Object.assign(
    {},
    partnerScenario(),
    DIRECT_URL ? scenario('internal', internalVus, 'internalTraffic') : {},
    DIRECT_URL && crewVus > 0 ? scenario('crewSignOn', crewVus, 'crewSignOn') : {},
    DIRECT_URL && checkInVus > 0 ? scenario('checkIn', checkInVus, 'checkIn') : {}
  )
};

const errorRate = new Rate('aetherion_errors');

// Aetherion's own clients identify themselves; partner traffic arrives through
// the published API.
const CLIENTS = {
  partner: 'Aetherion-PartnerAPI/3.2',
  station: 'Aetherion-StationOps/4.7',
  crew: 'Aetherion-CrewApp/2.9 (iOS)',
  checkin: 'Aetherion-Kiosk/5.1'
};

function headers(direct, client) {
  const h = { 'Content-Type': 'application/json', 'User-Agent': client || CLIENTS.partner };
  if (API_KEY && !direct) h['Ocp-Apim-Subscription-Key'] = API_KEY;
  return h;
}

function track(res) {
  const ok = res.status >= 200 && res.status < 400;
  errorRate.add(!ok);
  return ok;
}

// One pass of the operational journey against the given entry point.
function journey(base, direct, crewRepeats) {
  const h = headers(direct, direct ? CLIENTS.station : CLIENTS.partner);

  // Journey 1: passenger browses the flight board
  group('browse-flights', () => {
    const res = http.get(`${base}/api/flights`, { headers: h });
    check(res, { 'flights ok': (r) => track(r) });
  });
  sleep(Math.random() * 1);

  // Journey 2: check crew assignments
  group('crew-scheduling', () => {
    const res = http.get(`${base}/api/crew`, { headers: h });
    check(res, { 'crew ok': (r) => track(r) });
    for (let i = 0; i < crewRepeats; i++) {
      track(http.get(`${base}/api/crew`, { headers: h }));
    }
  });

  // Journey 3: create a booking / check-in (write path -> DB + Redis)
  group('booking', () => {
    const payload = JSON.stringify({ passenger: `PAX-${__VU}-${__ITER}`, flightNo: `AE${100 + (__ITER % 30)}` });
    const res = http.post(`${base}/api/book`, payload, { headers: h });
    check(res, { 'book ok': (r) => track(r) });
  });

  // Journey 4: baggage + telemetry background traffic
  group('ops-background', () => {
    track(http.get(`${base}/api/baggage/throughput`, { headers: h }));
    track(http.post(`${base}/api/telemetry`, JSON.stringify({ tailNo: 'G-AERO', metric: 'oil_temp', value: 90 }), { headers: h }));
  });

  sleep(1 + Math.random() * 2);
}

export function partnerTraffic() {
  // Shift-handover rush: crew rosters are pulled far harder than the rest of the
  // platform, so the crew path carries the concurrency on its own.
  if (MODE === 'crew-burst') {
    group('crew-scheduling', () => {
      const res = http.get(`${BASE_URL}/api/crew`, { headers: headers(false, CLIENTS.crew) });
      check(res, { 'crew ok': (r) => track(r) });
    });
    sleep(Math.random() * 0.2);
    return;
  }
  journey(BASE_URL, false, MODE === 'major' ? 6 : 0);
}

export function internalTraffic() {
  journey(DIRECT_URL, true, 0);
}

// Crews signing on for the departure wave pull the roster and little else.
export function crewSignOn() {
  const res = http.get(`${DIRECT_URL}/api/crew`, { headers: headers(true, CLIENTS.crew) });
  check(res, { 'crew ok': (r) => track(r) });
  sleep(Math.random() * 0.3);
}

// Passengers checking in at desks and kiosks.
export function checkIn() {
  const h = headers(true, CLIENTS.checkin);
  const payload = JSON.stringify({ passenger: `PAX-${__VU}-${__ITER}`, flightNo: `AE${100 + (__ITER % 30)}` });
  track(http.post(`${DIRECT_URL}/api/book`, payload, { headers: h }));
  track(http.get(`${DIRECT_URL}/api/bookings/count`, { headers: h }));
  sleep(Math.random() * 0.3);
}

export default function () {
  partnerTraffic();
}
