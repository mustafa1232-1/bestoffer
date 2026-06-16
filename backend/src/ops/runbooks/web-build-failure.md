# Web Build Failure Runbook

## Trigger
- GitHub Actions web build failure

## Immediate actions
1. Inspect failing workflow step and artifact logs.
2. Determine if failure blocks production readiness.

## Safe remediation
- Open incident issue.
- Request code fix prompt and PR.

## Recovery check
- CI web build job passes on latest branch.
