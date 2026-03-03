# Security Checklist (Production)

## Critical runtime env
- `JWT_SECRET` must be random and >= 32 chars.
- `JWT_SECRET_PREVIOUS` is optional and used only during key rotation window.
- `SUPER_ADMIN_PIN` and `SUPER_ADMIN_PHONE` must not use defaults.
- `AUTH_DEVICE_BINDING_REQUIRED=true`
- `AUTH_ALLOW_LEGACY_TOKENS=false` after rolling all users to new tokens.

## Key rotation
1. Set new secret as `JWT_SECRET` and move old one to `JWT_SECRET_PREVIOUS`.
2. Deploy backend.
3. Wait at least one full access-token TTL window.
4. Remove `JWT_SECRET_PREVIOUS`.
5. Deploy again.

## Account protection
- Keep `AUTH_MAX_FAILED_ATTEMPTS` between 5 and 10.
- Keep `AUTH_LOCK_MINUTES` between 10 and 30.
- Monitor `ACCOUNT_LOCKED` rate for attack spikes.

## Session hygiene
- Use `/api/auth/logout` on user sign-out.
- Use `/api/auth/logout-all` after sensitive account updates.
- Periodically revoke stale sessions.

## Network protection (WAF/CDN)
- Put Railway service behind Cloudflare or equivalent WAF.
- Apply IP reputation and bot protections at edge.
- Rate-limit `/api/auth/login` and `/api/auth/register` aggressively.

## Monitoring
- Alert on:
  - `INVALID_TOKEN` spikes
  - `INVALID_CREDENTIALS` spikes
  - `ACCOUNT_LOCKED` spikes
  - 5xx error bursts

## Operational check
Run:
```bash
npm run security:check
```

