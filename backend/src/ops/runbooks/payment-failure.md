# Payment Failure Runbook

## Trigger
- Payment authorization failures
- Payment capture failures
- Sudden payment error-rate spike

## Immediate actions
1. Verify incident severity and affected module in AI DEV SUPPORT.
2. Freeze high-risk automated actions.
3. Collect redacted gateway errors and request IDs.
4. Notify super admin and support teams.

## Safe remediation
- Retry idempotent payment intents only.
- Disable risky feature flag paths after approval.
- Open GitHub issue with payment-risk label.

## Do not do automatically
- Refunds, settlements, wallet adjustments, commission changes.
- Production deploy or merge.

## Recovery check
- Payment success rate stable for 30 minutes.
- No new SEV1 alerts.
