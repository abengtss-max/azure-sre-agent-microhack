# Runbook - API Management (APIM)

> Knowledge base runbook for the Azure SRE Agent. Service `aetherion-apim-*`,
> API `aetherion` (path `/aetherion`), product `aetherion-ops`.

## Role

APIM is the single public front door. Callers must send a subscription key
header `Ocp-Apim-Subscription-Key`. APIM forwards to the AKS `gateway` public IP
(`serviceUrl`), which in turn fans out to the microservices.

## Symptom: calls fail through APIM while the platform is healthy

- **Typical cause:** a policy change on the `aetherion-ops` product that
  redirects traffic away from the real backend - most often a
  `set-backend-service` override left behind by a release or an experiment.
- **Symptoms:**
  - k6 / clients see 5xx responses from the gateway.
  - The Ops Center looks healthy directly on the gateway IP but fails through
    APIM - the giveaway that the fault is at the edge, not in the services.
  - APIM analytics show errors with no matching failures in Application Insights.

### Remediate

1. Compare direct vs through-APIM:
   - Direct: `http://<gateway-ip>/api/status` -> 200 means the backend is fine.
   - Through APIM: `<apim-gateway-url>/aetherion/api/status` -> failure means the
     problem is the gateway or its policy.
2. Inspect the product policy for anything that changes routing or rejects
   callers (`set-backend-service`, `rate-limit*`, `check-header`).
3. Restore the default policy so the product inherits the API's backend. Treat
   this as a **customer-facing change** and confirm before applying.

## Symptom: HTTP 5xx or timeouts through APIM

- Check whether the backend `serviceUrl` points at the current gateway public IP
  (it is set during deployment; a changed LB IP breaks routing).
- Verify the AKS `gateway` service has an external IP and is healthy.

## Guardrails (APIM-specific)

- Policy edits affect **every** caller - always high-impact.
- Do not delete the API, product, or subscription as remediation.
- Prefer relaxing/removing an offending policy over recreating APIM objects.
- APIM (Consumption tier) is serverless and multi-tenant; it can have cold-start
  latency on the first call after idle. Avoid service-level operations unless
  clearly necessary.
