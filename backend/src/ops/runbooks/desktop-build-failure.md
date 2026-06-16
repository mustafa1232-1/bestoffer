# Desktop Build Failure Runbook

## Trigger
- Windows EXE build failure in CI

## Immediate actions
1. Collect compiler/lint/test logs.
2. Assess release impact and severity.

## Safe remediation
- Open issue with label `needs-human-review`.
- Request code-fix PR for low-risk changes.

## Recovery check
- Desktop build pipeline green.
