# API Latency Runbook

## Trigger
- p95 latency breach
- Datadog latency alerts

## Immediate actions
1. Verify if DB or downstream dependency is bottleneck.
2. Capture top slow routes with request IDs.
3. Escalate if user-facing checkout/taxi endpoints are impacted.

## Safe remediation
- Scale service resources.
- Restart non-sensitive service after approval.
- Disable expensive non-critical feature flags.

## Recovery check
- p95 latency back under threshold for 20 minutes.
