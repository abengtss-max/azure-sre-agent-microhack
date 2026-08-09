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
      .setSendLiveMetrics(true)
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
