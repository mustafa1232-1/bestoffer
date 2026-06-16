# Flutter Crash Runbook

## Trigger
- Sentry crash spike on Android/iOS/Web/Desktop

## Immediate actions
1. Identify app version and platform segment.
2. Validate crash stack redaction.
3. Notify super admin for SEV1/SEV2 incidents.

## Safe remediation
- Open GitHub issue with crash details.
- Request low-risk code fix PR when eligible.

## Recovery check
- Crash-free sessions trend recovers.
