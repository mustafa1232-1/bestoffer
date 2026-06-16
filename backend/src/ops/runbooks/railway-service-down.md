# Railway Service Down Runbook

## Trigger
- Railway deployment/service unavailable
- Health endpoint failing

## Immediate actions
1. Confirm status via Railway tool and /health endpoint.
2. Escalate if production traffic impacted.

## Safe remediation
- Restart non-sensitive service after approval.
- Prepare rollback plan; execute only with explicit super admin approval.

## Recovery check
- Health and readiness endpoints green.
