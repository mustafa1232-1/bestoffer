# Kysely Adoption Plan

## Current State

- Status: `NOT_INSTALLED / NOT_STARTED`
- PostgreSQL remains the database source of truth.
- Numbered SQL migrations under `backend/sql/*.sql` remain the only schema migration system.
- No Kysely runtime layer is present yet in this baseline.

## Policy

- Do not replace the existing SQL migration flow.
- Do not convert the backend wholesale to TypeScript.
- Do not start with orders, taxi, notifications, social, or finance in bulk.
- Use Kysely only as a gradual typed query layer after P0 blockers are closed.

## Recommended Pilot

- Merchants
- Categories
- Products

## Current Guardrails

- No runtime Kysely client has been added.
- No production command has changed for Kysely.
- No repository has been converted yet.
- SQL migrations remain the only schema source of truth.

## Safe Pilot Steps

1. Document the current schema.
2. Generate or read types from the live schema without mutating data.
3. Convert one repository path.
4. Add parity tests against the current raw-SQL behavior.
5. Measure correctness and performance.
6. Keep the pilot only if it stays behaviorally identical and deploy-safe.

## Stop Conditions

- Build complexity increases materially
- Runtime transpilation becomes brittle
- Response shapes drift
- Deployment risk increases
- Migration confusion appears
