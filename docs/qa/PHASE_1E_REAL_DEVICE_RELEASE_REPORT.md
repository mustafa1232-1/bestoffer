# Phase 1E Report - P0 Real Device QA, Deployment Confirmation, and Internal Release Gate

## Summary

- Working branch: `closure/full-application-closure`
- Starting HEAD: `4034661545ea66366a6bc741b3327d13b4767b0d`
- Final HEAD: `4034661545ea66366a6bc741b3327d13b4767b0d`
- Git status after documentation and artifact capture: clean
- Final decision: `BLOCKED`

This phase confirmed the deployed backend revision and rebuilt current signed QA APKs for the affected mobile flavors. Real-device QA could not be completed because no physical Android devices were available in the workspace; Flutter only detected desktop and web targets.

## Deployment Confirmation

- Local HEAD: `4034661545ea66366a6bc741b3327d13b4767b0d`
- Pushed branch HEAD: `4034661545ea66366a6bc741b3327d13b4767b0d`
- Railway service: `bestoffer`
- Railway environment: `production`
- Railway deployment id: `499746db-3ec6-426c-921d-4f7024c87956`
- Deployment status: `SUCCESS`
- Deployed commit: `4034661545ea66366a6bc741b3327d13b4767b0d`
- `/health`: `200`
- `/ready`: `200`

## Test Baseline

- `flutter analyze` passed
- `flutter test` passed, `372` tests
- `cd backend && npm test` passed, `256` tests
- `cd backend && npm run verify:release:local` passed
- `node --env-file=.env.test src/scripts/taxiE2ECheck.js` passed
- `railway run --service bestoffer npm run verify:release:runtime` passed

## Devices Available

- Physical Android devices: none detected
- `adb`: not available on PATH in this shell
- `flutter devices` only reported:
  - Windows desktop
  - Chrome
  - Edge

This means the following required Phase 1E flows remain blocked:

- foreground push on a real device
- background push on a real device
- killed-app push on a real device
- cold-start notification tap on a real device
- real taxi location/session churn
- real store/delivery notification tap validation

## Current Signed QA APKs

### User

- Package ID: `com.maslaki.user`
- Version name: `1.0.1`
- Version code: `9`
- Artifact: `qa_artifacts/phase_1e_android_apks/user/app-user-release.apk`
- Size: `349283795` bytes, `333.10 MB`
- SHA-256: `9DD10CFBB5EF5100537AFBCAC26C4BBA1EB4AD3E321CA8C2E9C46BC12D71386C`
- Signing certificate DN: `CN=Mustafa Salam, O=Maslaki, L=Baghdad, ST=Baghdad, C=IQ`
- Signing certificate SHA-256: `f7d826650e7e48c4bde78cc9d33d26d915af832fd87dc47d576616e2669881fa`

### Store

- Package ID: `com.maslaki.store`
- Version name: `1.0.1`
- Version code: `9`
- Artifact: `qa_artifacts/phase_1e_android_apks/store/app-store-release.apk`
- Size: `345351639` bytes, `329.35 MB`
- SHA-256: `33CF2CC185A52494ED4A53CDE85247B7060B456C9308D8965FE6C344F7523994`
- Signing certificate DN: `CN=Mustafa Salam, O=Maslaki, L=Baghdad, ST=Baghdad, C=IQ`
- Signing certificate SHA-256: `f7d826650e7e48c4bde78cc9d33d26d915af832fd87dc47d576616e2669881fa`

### Delivery

- Package ID: `com.maslaki.delivery`
- Version name: `1.0.1`
- Version code: `9`
- Artifact: `qa_artifacts/phase_1e_android_apks/delivery/app-delivery-release.apk`
- Size: `345171427` bytes, `329.18 MB`
- SHA-256: `6012AB09E57F76F114086CF2E0692CE54CD271000FD712D57A59B5ACB3ADDC3B`
- Signing certificate DN: `CN=Mustafa Salam, O=Maslaki, L=Baghdad, ST=Baghdad, C=IQ`
- Signing certificate SHA-256: `f7d826650e7e48c4bde78cc9d33d26d915af832fd87dc47d576616e2669881fa`

### Captain

- Package ID: `com.maslaki.captain`
- Version name: `1.0.1`
- Version code: `9`
- Artifact: `qa_artifacts/phase_1e_android_apks/captain/app-captain-release.apk`
- Size: `345204191` bytes, `329.21 MB`
- SHA-256: `174480004D4F87B8C9457FC7993FFBCCE1AAA6BA7B8631B805A1243E0F14BC56`
- Signing certificate DN: `CN=Mustafa Salam, O=Maslaki, L=Baghdad, ST=Baghdad, C=IQ`
- Signing certificate SHA-256: `f7d826650e7e48c4bde78cc9d33d26d915af832fd87dc47d576616e2669881fa`

## Build Notes

- Current signed APKs were rebuilt from the current clean HEAD using explicit flavors:
  - `user`
  - `store`
  - `delivery`
  - `captain`
- The release signing configuration resolved from `android/key.properties`.
- Company and Pharmacy were not rebuilt because the changes in this phase are confined to the root mobile surfaces and taxi/backend paths; no shared compile-safe change forced those separate apps to rebuild.
- Signed AAB generation was deferred because the real-device Phase 1E gate is still blocked.

## Remaining Blockers

- No physical Android devices were available for real-device QA.
- Foreground/background/killed-app push flows remain blocked.
- Cold-start notification tap validation remains blocked.
- Taxi live-location and notification session churn remain blocked on real devices.
- Store/Delivery/User/Captain device tap flows remain blocked.
- AAB generation remains deferred until the device gate is available or the phase is explicitly re-scoped.

## Fixes Applied During This Phase

- No new code defects were discovered that required a business-logic fix during this Phase 1E run.
- Deployment confirmation was completed via `scripts/railway_deploy_backend.ps1`.
- Current APKs were rebuilt and verified against the current HEAD.

## Commit / Deployment Trace

- Relevant backend/app commit: `4034661545ea66366a6bc741b3327d13b4767b0d`
- Phase 1D report updated with deployment confirmation.
- Railway deployment id: `499746db-3ec6-426c-921d-4f7024c87956`

## Final Decision

`BLOCKED`

Reason: the phase requires real-device QA evidence, and no physical Android devices were available in this workspace.

