# Database Errors Runbook

## Trigger
- Connection pool exhaustion
- Query timeout spike
- Primary DB unavailable

## Immediate actions
1. Mark incident as SEV1 if order/payment flow impacted.
2. Block destructive or migration actions.
3. Gather redacted DB errors and health evidence.

## Safe remediation
- Restart service workers (not DB) after approval.
- Enable read-only degradation mode if supported.

## Forbidden automatic actions
- Destructive SQL
- Production schema migrations

## Recovery check
- DB health endpoint stable.
- Application error rate normalized.
