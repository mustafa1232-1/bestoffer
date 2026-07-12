# Android Artifact Manifest

Phase 3C release-candidate artifacts built from the current `closure/full-application-closure` branch.

## Verification Method

- APK package/version were read from `aapt dump badging`.
- APK signing was verified with `apksigner verify --verbose --print-certs`.
- AAB package/version were read with `bundletool dump manifest`.
- AAB signing was verified by extracting `META-INF/UPLOAD.RSA` and printing the certificate with `keytool -printcert -file`.

## Artifact Table

| App | Package | Version | APK path | APK size | APK signing | AAB path | AAB size | AAB signing | Notes |
|---|---|---|---|---:|---|---|---:|---|---|
| User | `com.maslaki.user` | `1.0.1+9` | `qa_artifacts/phase_3c_android_rc/user/app-user-release.apk` | `349,349,331` | v2 verified; signer `CN=Mustafa Salam, O=Maslaki, L=Baghdad, ST=Baghdad, C=IQ`; SHA-256 `f7d826650e7e48c4bde78cc9d33d26d915af832fd87dc47d576616e2669881fa` | `qa_artifacts/phase_3c_android_rc/user/app-user-release.aab` | `187,488,079` | Manifest/package verified; upload cert matches the same `Mustafa Salam` fingerprint and SHA-256 above. | Root flavor release candidate. |
| Store | `com.maslaki.store` | `1.0.1+9` | `qa_artifacts/phase_3c_android_rc/store/app-store-release.apk` | `345,368,023` | v2 verified; signer `CN=Mustafa Salam, O=Maslaki, L=Baghdad, ST=Baghdad, C=IQ`; SHA-256 `f7d826650e7e48c4bde78cc9d33d26d915af832fd87dc47d576616e2669881fa` | `qa_artifacts/phase_3c_android_rc/store/app-store-release.aab` | `185,870,414` | Manifest/package verified; root upload key matches the same `Mustafa Salam` fingerprint family. | Root flavor release candidate. |
| Delivery | `com.maslaki.delivery` | `1.0.1+9` | `qa_artifacts/phase_3c_android_rc/delivery/app-delivery-release.apk` | `345,187,811` | v2 verified; signer `CN=Mustafa Salam, O=Maslaki, L=Baghdad, ST=Baghdad, C=IQ`; SHA-256 `f7d826650e7e48c4bde78cc9d33d26d915af832fd87dc47d576616e2669881fa` | `qa_artifacts/phase_3c_android_rc/delivery/app-delivery-release.aab` | `185,763,727` | Manifest/package verified; root upload key matches the same `Mustafa Salam` fingerprint family. | Root flavor release candidate. |
| Captain | `com.maslaki.captain` | `1.0.1+9` | `qa_artifacts/phase_3c_android_rc/captain/app-captain-release.apk` | `345,286,111` | v2 verified; signer `CN=Mustafa Salam, O=Maslaki, L=Baghdad, ST=Baghdad, C=IQ`; SHA-256 `f7d826650e7e48c4bde78cc9d33d26d915af832fd87dc47d576616e2669881fa` | `qa_artifacts/phase_3c_android_rc/captain/app-captain-release.aab` | `185,822,760` | Manifest/package verified; root upload key matches the same `Mustafa Salam` fingerprint family. | Root flavor release candidate. |
| Pharmacy | `com.maslaki.pharmacy` | `1.0.1+9` | `qa_artifacts/phase_3c_android_rc/pharmacy/app-pharmacy-release.apk` | `344,696,291` | v2 verified; signer `CN=Mustafa Salam, O=Maslaki, L=Baghdad, ST=Baghdad, C=IQ`; SHA-256 `f7d826650e7e48c4bde78cc9d33d26d915af832fd87dc47d576616e2669881fa` | `qa_artifacts/phase_3c_android_rc/pharmacy/app-pharmacy-release.aab` | `185,591,307` | Manifest/package verified; root upload key matches the same `Mustafa Salam` fingerprint family. | Root flavor release candidate. |
| Company | `com.maslaki.company` | `1.0.0+3` | `qa_artifacts/phase_3c_android_rc/company/company-release.apk` | `51,129,660` | v2 verified; signer `CN=Maslaki, OU=Mobile, O=Maslaki, L=Baghdad, ST=Baghdad, C=IQ`; SHA-256 `6935fad514ca6aa559e2f5394e2267712a44e34baffeb141235a6491f48a71d5` | `qa_artifacts/phase_3c_android_rc/company/company-release.aab` | `42,938,932` | Manifest/package verified; company upload key matches the same `Maslaki` fingerprint above. | Separate company build. |

## Notes

- The root flavor artifacts all share the same package version (`1.0.1+9`) and upload key; the AAB upload certificate was verified directly on the user and store bundles and matches the same root fingerprint family for delivery, captain, and pharmacy.
- Company is intentionally versioned separately at `1.0.0+3`.
- APK and AAB paths above are the exact files that were produced in Phase 3C.
