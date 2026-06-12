# Postgres Recovery Runbook

This production environment now uses a **single PostgreSQL primary**.

Normal operation:
- `DATABASE_URL` points to the only active PostgreSQL database
- the app reads and writes to `DATABASE_URL`
- there is no standby promotion path inside the application

## 1. Detect the incident

Check:

```bash
curl https://bestoffer-production.up.railway.app/health
curl https://bestoffer-production.up.railway.app/ready
```

Symptoms of database failure:
- `/ready` returns `503`
- `/health.db.primary.ok = false`

## 2. Decide the recovery action

Choose one:
- restart the existing PostgreSQL service if the failure is transient
- restore the PostgreSQL service from backup if the volume is damaged
- recreate PostgreSQL and allow the app to rebuild schema from migrations if starting fresh is acceptable

## 3. Point the app at the recovered database

Update Railway variables for `bestoffer`:
- set `DATABASE_URL` to the recovered PostgreSQL URL
- keep `RUN_SQL_MIGRATIONS=true` if schema bootstrap is required

Then restart or redeploy the app.

## 4. Verify recovery

Check:

```bash
curl https://bestoffer-production.up.railway.app/health
curl https://bestoffer-production.up.railway.app/ready
```

Healthy target state:
- `/ready` returns `200`
- `/health.db.mode = single_primary`
- `/health.db.primary.ok = true`
- application write paths succeed

## 5. What the app will and will not do

The app will:
- probe primary database health
- expose readiness and detailed health
- retry brief transient primary connection failures

The app will not:
- auto-promote another database
- silently switch writes to a fallback database
- pretend a secondary database is current
