# Review Account Validation

Do not commit real review credentials. Provide them through environment variables, CI secrets, or a local shell session.

Run from `backend`:

```powershell
$env:MASLAKI_API_BASE_URL = "https://bestoffer-production.up.railway.app"
$env:MASLAKI_CUSTOMER_REVIEW_PHONE = "[CUSTOMER_REVIEW_PHONE]"
$env:MASLAKI_CUSTOMER_REVIEW_PIN = "[CUSTOMER_REVIEW_PIN]"
$env:MASLAKI_PROVIDER_REVIEW_PHONE = "[PROVIDER_REVIEW_PHONE]"
$env:MASLAKI_PROVIDER_REVIEW_PIN = "[PROVIDER_REVIEW_PIN]"
npm run verify:review-accounts
```

Fallback aliases are also accepted for the customer account:

- `MASLAKI_REVIEW_PHONE`
- `MASLAKI_REVIEW_PIN`

## What The Script Verifies

- API base URL is HTTPS and not localhost/private network.
- `/health` returns `200`.
- `/ready` does not return a server error.
- Invalid credentials are rejected safely and do not expose raw request UUIDs.
- Customer review credentials sign in and can call `/api/me`.
- Provider review credentials sign in, are approved, can call provider workspace, and do not receive payment/subscription/receipt/cash activation copy in application status JSON.

## Acceptance Criteria

- Review customer credentials are active on production.
- Review provider credentials are active, approved, and require no payment.
- No OTP, SMS verification, manual approval, or location presence blocks review.
- PIN leading zeroes are preserved by the app.
- `07...`, `964...`, and `+964...` phone formats normalize to the same local Iraqi mobile format.
