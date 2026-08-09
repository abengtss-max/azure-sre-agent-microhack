# Runbook - API Management (APIM)

> Knowledge base runbook for the Azure SRE Agent. Service `aetherion-apim-*`,
> API `aetherion` (path `/aetherion`), product `aetherion-ops`.

## Role

APIM is the single public front door. Callers must send a subscription key
header `Ocp-Apim-Subscription-Key`. APIM forwards to the AKS `gateway` public IP
(`serviceUrl`), which in turn fans out to the microservices.

## Symptom: clients receive HTTP 429 (Too Many Requests)

- **Cause in this env:** a restrictive `rate-limit-by-key` policy on the
  `aetherion-ops` product (e.g. 5 calls / 60s) throttles traffic.
- **Symptoms:**
  - k6 / clients see 429 responses; Ops Center may look healthy directly on the
    gateway IP but fails through APIM.
  - APIM analytics show a spike in 429s.

### Remediate

1. Compare direct vs through-APIM:
   - Direct: `http://<gateway-ip>/api/status` -> 200 means backend is fine.
   - Through APIM: `<apim-gateway-url>/aetherion/api/status` -> 429 means policy.
2. Inspect the product policy for a `rate-limit-by-key` element.
3. Restore a sane policy (remove/relax the rate limit). Treat this as a
   **customer-facing change** and confirm before applying.

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
