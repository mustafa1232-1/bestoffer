# Notification Failure Runbook

## Trigger
- Push send failures
- Delivery latency anomalies

## Immediate actions
1. Check push provider credentials and token health.
2. Review failed delivery events.
3. Notify super admin if SEV2+.

## Safe remediation
- Retry queue drains.
- Temporarily reduce notification throughput.

## Recovery check
- Success rate restored and failure queue draining.
