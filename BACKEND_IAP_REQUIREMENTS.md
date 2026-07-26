# Backend IAP Requirements

The repository currently contains a backend service-provider subscription workflow based on admin offers and cash confirmation. That is not sufficient for a paid digital provider subscription on iOS.

Do not grant provider digital access from an unverified client boolean, fake receipt, manual cash confirmation, reviewer detection, locale flag, date flag, or remote-config bypass.

## Required Product IDs

Recommended identifiers:
- `maslaki.provider.monthly`
- `maslaki.provider.yearly`

These must be created in App Store Connect before the iOS client can sell them.

## Required Endpoints

### `POST /api/iap/apple/transactions`

Purpose: verify a StoreKit transaction and attach the resulting entitlement to the signed-in account.

Authentication: required user bearer token.

Request:

```json
{
  "transactionId": "2000000000000000",
  "originalTransactionId": "2000000000000000",
  "productId": "maslaki.provider.monthly",
  "environment": "Sandbox",
  "appAccountToken": "uuid-if-used"
}
```

Response:

```json
{
  "entitlement": {
    "productId": "maslaki.provider.monthly",
    "status": "active",
    "environment": "Sandbox",
    "originalTransactionId": "2000000000000000",
    "purchaseDate": "2026-07-26T00:00:00.000Z",
    "expiresDate": "2026-08-26T00:00:00.000Z",
    "revokedAt": null,
    "gracePeriodExpiresAt": null
  }
}
```

### `GET /api/iap/apple/entitlement`

Purpose: refresh the current user's provider subscription entitlement at app launch and foreground resume.

Authentication: required user bearer token.

Response:

```json
{
  "entitlement": {
    "status": "active",
    "productId": "maslaki.provider.monthly",
    "expiresDate": "2026-08-26T00:00:00.000Z"
  }
}
```

## Verification Rules

- Verify transactions with Apple-supported App Store Server mechanisms.
- Store `transactionId`, `originalTransactionId`, `productId`, `environment`, `purchaseDate`, `expiresDate`, `revocationDate`, state, and linked user/provider id.
- Separate Sandbox and Production verification.
- Make transaction processing idempotent by `originalTransactionId` and transaction id.
- Complete app-side transactions only after server processing succeeds or returns an already-processed success state.
- Never log full receipts, signed transaction payloads, bearer tokens, PINs, or personal data.
- Handle renewal, expiration, refund, revocation, billing retry, and grace period.
- Process App Store Server Notifications V2 for subscription lifecycle changes.
- Do not use cash, bank transfer, WhatsApp, phone, invoice, QR, or external website payment to unlock provider digital access on iOS.

## Entitlement States

- `active`
- `pending`
- `expired`
- `revoked`
- `billing_retry`
- `grace_period`
- `none`

The provider workspace/listing entitlement must derive from verified server state, not from client-only state.

