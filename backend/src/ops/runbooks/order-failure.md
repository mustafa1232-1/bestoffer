# Order Failure Runbook

## Trigger
- Order creation/placement failures
- Checkout endpoint 5xx errors

## Immediate actions
1. Confirm service health and DB readiness.
2. Review affected module and symptoms from AI DEV SUPPORT.
3. Notify super admin for medium/high risk actions.

## Safe remediation
- Restart non-sensitive service with approval.
- Disable unstable feature flag path.
- Create issue and code-fix request.

## Recovery check
- New orders can be created end-to-end.
- Error rate returns to baseline.
