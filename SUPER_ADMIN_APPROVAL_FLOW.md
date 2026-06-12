# Super Admin Approval Flow

## Low risk
- Single approve action allowed.

## Medium risk
- Approve with visible summary/risk/rollback plan.

## High/Critical
- Single super admin approval allowed.
- Mandatory typed confirmation (`APPROVE` or `CONFIRM`).
- Audit log required with IP/user-agent/userId/timestamp.

## Reject
- Reason is captured in `ops_actions` and `ops_action_approvals`.
