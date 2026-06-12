# Safe Action Policy

## Always forbidden for AI
- Merge to main
- Production deploy
- Secrets/env changes
- Destructive SQL
- Automatic payment/wallet/settlement/commission mutations

## Auto allowed
- Read alerts/logs/metrics
- Analyze incidents
- Notify super admin
- Create issue
- Low-risk code-fix request flow

## Requires super admin approval
- Medium risk actions
- High/Critical actions with typed confirmation (`APPROVE` / `CONFIRM`)
