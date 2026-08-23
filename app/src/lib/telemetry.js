'use strict';

// Application Insights initialization. No-ops safely if no connection string is
// configured, so the app also runs locally without Azure.
let appInsights = null;
let client = null;

function initTelemetry(role) {
  const conn = process.env.APPLICATIONINSIGHTS_CONNECTION_STRING;
  if (!conn) {
    console.log('[telemetry] APPLICATIONINSIGHTS_CONNECTION_STRING not set - telemetry disabled');
    return;
  }
  try {
    appInsights = require('applicationinsights');
    appInsights
      .setup(conn)
      .setAutoCollectRequests(true)
      .setAutoCollectPerformance(true, true)
      .setAutoCollectDependencies(true)
      .setAutoCollectExceptions(true)
      // Off deliberately: the Live Metrics endpoint is not reachable from the
      // cluster, and QuickPulseSender retries flood every pod's log with
      // ETIMEDOUT. Those logs are the main investigation surface in this
      // workshop, so the noise reads as a red herring. Requests, dependencies
      // and exceptions are unaffected.
      .setSendLiveMetrics(false)
      .setUseDiskRetryCaching(true);

    appInsights.defaultClient.context.tags[appInsights.defaultClient.context.keys.cloudRole] =
      `aetherion-${role}`;
    appInsights.start();
    client = appInsights.defaultClient;
    console.log(`[telemetry] Application Insights started for role=${role}`);
  } catch (err) {
    console.error('[telemetry] failed to start Application Insights', err.message);
  }
}

function trackEvent(name, properties) {
  if (client) {
    client.trackEvent({ name, properties });
  }
}

function trackMetric(name, value, properties) {
  if (client) {
    client.trackMetric({ name, value, properties });
  }
}

module.exports = { initTelemetry, trackEvent, trackMetric };
