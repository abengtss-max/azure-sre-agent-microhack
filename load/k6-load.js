import http from 'k6/http';
import { check, sleep, group } from 'k6';
import { Rate } from 'k6/metrics';

// Aetherion AirOps traffic generator.
// Drives realistic mixed operational journeys through the APIM gateway so
// metrics/logs stay populated and injected faults produce visible signal.
//
// Configure via environment variables:
//   BASE_URL   - APIM gateway base URL (required), e.g. https://<apim>.azure-api.net/aetherion
//   MODE       - "normal" (default), "surge", or "crew-burst"
//   VUS        - override virtual users
//   API_KEY    - APIM subscription key (optional; sent as Ocp-Apim-Subscription-Key)

const BASE_URL = (__ENV.BASE_URL || 'http://localhost:8080').replace(/\/$/, '');
const MODE = __ENV.MODE || 'normal';
const API_KEY = __ENV.API_KEY || '';

const normalVus = parseInt(__ENV.VUS || '25', 10);
const surgeVus = parseInt(__ENV.VUS || '120', 10);
const burstVus = parseInt(__ENV.VUS || '250', 10);

// A crew-roster rush (shift handover) concentrates traffic on one service.
const crewBurstOptions = {
  scenarios: {
    crewBurst: {
      executor: 'constant-vus',
      vus: burstVus,
      duration: __ENV.DURATION || '24h'
    }
  }
};

export const options =
  MODE === 'crew-burst'
    ? crewBurstOptions
    : MODE === 'surge'
    ? {
        // A departure-wave surge holds a sustained, closed-loop concurrency.
        // Ramping stages made the offered load vary while an incident was open,
        // so the same fault produced a different symptom minute to minute.
        scenarios: {
          surge: {
            executor: 'constant-vus',
            vus: surgeVus,
            duration: __ENV.DURATION || '24h'
          }
        }
      }
    : {
        scenarios: {
          steady: {
            executor: 'constant-vus',
            vus: normalVus,
            duration: __ENV.DURATION || '24h'
          }
        }
      };

const errorRate = new Rate('aetherion_errors');

function headers() {
  const h = { 'Content-Type': 'application/json' };
  if (API_KEY) h['Ocp-Apim-Subscription-Key'] = API_KEY;
  return h;
}

function track(res) {
  const ok = res.status >= 200 && res.status < 400;
  errorRate.add(!ok);
  return ok;
}

export default function () {
  // Shift-handover rush: crew rosters are pulled far harder than the rest of the
  // platform, so the crew path carries the concurrency on its own.
  if (MODE === 'crew-burst') {
    group('crew-scheduling', () => {
      const res = http.get(`${BASE_URL}/api/crew`, { headers: headers() });
      check(res, { 'crew ok': (r) => track(r) });
    });
    sleep(Math.random() * 0.2);
    return;
  }

  // Journey 1: passenger browses the flight board
  group('browse-flights', () => {
    const res = http.get(`${BASE_URL}/api/flights`, { headers: headers() });
    check(res, { 'flights ok': (r) => track(r) });
  });
  sleep(Math.random() * 1);

  // Journey 2: check crew assignments
  group('crew-scheduling', () => {
    const res = http.get(`${BASE_URL}/api/crew`, { headers: headers() });
    check(res, { 'crew ok': (r) => track(r) });
  });

  // Journey 3: create a booking / check-in (write path -> DB + Redis)
  group('booking', () => {
    const payload = JSON.stringify({ passenger: `PAX-${__VU}-${__ITER}`, flightNo: `AE${100 + (__ITER % 30)}` });
    const res = http.post(`${BASE_URL}/api/book`, payload, { headers: headers() });
    check(res, { 'book ok': (r) => track(r) });
  });

  // Journey 4: baggage + telemetry background traffic
  group('ops-background', () => {
    track(http.get(`${BASE_URL}/api/baggage/throughput`, { headers: headers() }));
    track(http.post(`${BASE_URL}/api/telemetry`, JSON.stringify({ tailNo: 'G-AERO', metric: 'oil_temp', value: 90 }), { headers: headers() }));
  });

  sleep(1 + Math.random() * 2);
}
