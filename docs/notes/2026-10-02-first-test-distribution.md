# First test distribution: console steps

This note lists what the operator does outside the repository before the first TestFlight build and the first Google Play internal testing release of version `1.0.0` build `1`.
The brief is `docs/plans/2026-10-02-release-prep.md`.
Nothing in this list was done by an agent: no store record, no upload, no signing with a real key, no Firebase change.

## Open items before an external TestFlight review

The TestFlight overview says: "When you add the first build of your app to a group, the build gets sent to App Review" (https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview, read on 2026-10-02), and these items can block that review.
An internal group holds up to 100 App Store Connect users of your team.

1. **Account deletion (App Store Review Guideline 5.1.1(v)).** The app signs in anonymously at start, and Apple asks for an in-app way to delete automatically created ("guest") accounts and their data. The app has none. Pull request 19 quotes Apple's text under "Account deletion".
2. **Photo location (issue 20).** On Android, a published photo can keep the GPS tags that the camera app wrote. iOS is not checked.
3. **Anonymous account clean-up (issue 21).** Firebase can delete an anonymous account after 30 days. The next sign-in gets a new user ID, and the rules then refuse every publish to the existing pages of that phone.
4. **Support contact.** `support_url.txt` names the landing page `https://kkomkkomi.web.app/`, which has no working contact: its inquiry form is a preview that sends nothing. Guideline 1.5 says: "Make sure your app and its Support URL include an easy way to contact you". Add a contact to that page, or give another support URL.
5. **Privacy policy.** The pages at `/privacy/` and `/privacy/en/` exist only after the next Hosting deploy, which needs the operator's approval. They still hold the operator placeholders that pull request 19 lists, such as the privacy officer and the contact.

## Values

| Item                           | Value                                                                                            |
| ------------------------------ | ------------------------------------------------------------------------------------------------ |
| Bundle ID and application ID   | `kr.donminzzi.kkomkkomi` (production flavor)                                                     |
| Version                        | `1.0.0`, build `1`, from `pubspec.yaml`                                                          |
| iOS minimum version            | 15.0 (`IPHONEOS_DEPLOYMENT_TARGET`)                                                              |
| Android minimum and target SDK | 24 and 36, read from the built bundle                                                            |
| Privacy policy                 | `https://kkomkkomi.web.app/privacy/` (Korean), `https://kkomkkomi.web.app/privacy/en/` (English) |
| App Store categories           | Business, then Productivity (`fastlane/metadata/ios/*_category.txt`)                             |

`DEVELOPMENT_TEAM` is not set in `ios/Runner.xcodeproj`.
Set it in Xcode (Runner target, Signing & Capabilities) only after you confirm the team ID.

## Apple

1. **Bundle ID.** In Certificates, Identifiers & Profiles, register the explicit App ID `kr.donminzzi.kkomkkomi`. The app uses no capability that needs a switch there: no push notification, no sign in with Apple, no app group.
2. **App Store Connect app record.** Create a new iOS app with the bundle ID above, the primary language Korean, the name `꼼꼬미`, and an SKU of your choice. App Store Connect rejects a name that another app uses.
3. **App information.** Set the category, the privacy policy URL, and the content rights. Answer the age rating questions.
4. **Export compliance.** The app sends data only over HTTPS through the Firebase SDKs and has no encryption of its own. App Store Connect asks about this for each build. Adding `ITSAppUsesNonExemptEncryption` to `Info.plist` answers it once, and is a separate change.
5. **Build and upload.** Set the team, then run `merry run build ipa` and upload the IPA with Xcode Organizer or Transporter. The build needs `ios/Runner/GoogleService-Info.plist` from `flutterfire configure`, as `CLAUDE.md` says.
6. **TestFlight.** Make an internal group, add the testers, and paste the "What to Test" text below. For an external group, settle the open items above first.
7. **App Privacy.** Enter the answers in "Draft answers for App Privacy" below.

### "What to Test" for build 1

App Store Connect has no "What's New" field for the first version of an app: "This property isn't available for the first version of the app but required for all subsequent versions" (App Store Connect Help, "Platform version information", https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information).
So `fastlane/metadata/ios/` holds no `release_notes.txt`, and this text goes into the TestFlight "What to Test" field instead.

```plaintext
ko:
• 거래처와 구역을 저장해 두면, 방문할 때마다 같은 구역으로 시작할 수 있어요.
• 구역마다 청소 전후 사진을 짝지어 찍고 메모를 남길 수 있어요.
• 보고서를 PDF로 공유하거나, 거래처가 로그인 없이 여는 링크로 보낼 수 있어요.

en-US:
• Save clients and their zones, and start each visit with the same zones.
• Take paired before and after photos of each zone and add a note.
• Share the report as a PDF, or as a link that your client opens without signing in.
```

## Google Play

1. **Play Console app.** Create the app with the default language Korean (`ko-KR`), the name from `fastlane/metadata/android/ko-KR/title.txt`, the type App, and free or paid as you decide.
2. **Store settings.** Choose the category Business. Enter a contact email, which Play requires.
3. **App content.** Enter the privacy policy URL. For app access, all functions work without a login. Ads: none. Answer the content rating questions and the target audience. Enter the Data safety answers below.
4. **Internal testing track.** Create a release on the internal testing track, upload the App Bundle, add the testers' email list, and use `fastlane/metadata/android/<locale>/changelogs/1.txt` as the release notes.
5. **App signing.** Play App Signing keeps the key that signs the app for users. The bundle that you upload is signed with your upload key.

### The upload key

- Make it once with `keytool -genkeypair` (RSA 2048, a long validity) and keep the keystore and its passwords outside the repository, with a backup. `.gitignore` already ignores `*.jks`, `*.keystore`, and `key.properties`.
- `android/app/build.gradle.kts` reads it from the four variables `ANDROID_KEYSTORE_PATH`, `ANDROID_KEYSTORE_ALIAS`, `ANDROID_KEYSTORE_PASSWORD`, and `ANDROID_KEYSTORE_PRIVATE_KEY_PASSWORD`, or from `android/key.properties` when `ANDROID_KEYSTORE_PATH` is not set.
- Then run `merry run build aab` with those variables, and upload `build/app/outputs/bundle/productionRelease/app-production-release.aab`. The bundle needs `android/app/google-services.json` from `flutterfire configure`.
- Play Console Help says: "If you lose your upload key or suspect that it was compromised, you are not locked out of your app", and a new upload key is then registered through a reset request (https://support.google.com/googleplay/android-developer/answer/9842756, read on 2026-10-02). The same page says that a new app is enrolled in Play App Signing with keys that Google generates.

## Firebase

- The Firebase macOS app is registered as `com.example.myApp`, and the macOS production bundle ID is now `kr.donminzzi.kkomkkomi`. macOS is not a target, so this needs no action now. Before a macOS production build, register the macOS app again and run `flutterfire configure`.
- Hosting must be deployed before a store listing names the privacy policy URL. A deploy needs your approval.

## Draft answers for App Privacy (App Store Connect)

Sources: `lib/firebase/firebase_publisher.dart` (what a link share uploads), `lib/firebase/firebase_identity.dart` (anonymous sign-in), the privacy policy pages of pull request 19, and Google's list of the data that each Firebase SDK collects (https://firebase.google.com/docs/android/play-data-disclosure, read on 2026-10-02).
The app sends nothing before the person taps the link share, except the anonymous sign-in at start.
No data is used for tracking, and no data goes to an ad network or a data broker.

| Data type                          | Collected                   | Linked to the user | Purpose           | Why                                                                                                                                                     |
| ---------------------------------- | --------------------------- | ------------------ | ----------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Identifiers: User ID               | Yes                         | Yes                | App Functionality | The anonymous Firebase user ID owns each client page (`ownerUid`).                                                                                      |
| User Content: Photos or Videos     | Yes                         | Yes                | App Functionality | A link share uploads the before and after photos of the visit.                                                                                          |
| User Content: Other User Content   | Yes                         | Yes                | App Functionality | A link share uploads the company name, the client name, the zone names, the notes, and the visit date.                                                  |
| Location: Precise Location         | Yes until issue 20 is fixed | Yes                | App Functionality | A photo can keep the GPS tags of the camera app (Android, checked in code). iOS is not checked.                                                         |
| Diagnostics: Other Diagnostic Data | Yes                         | No                 | Analytics         | The Firebase Auth, Firestore, and Installations privacy manifests declare it as not linked, not tracking, for Analytics (see "Privacy manifest" below). |

Firebase Authentication also processes the IP address and the user agent of each sign-in for security and abuse prevention.
Apple's page says: "You need to identify all of the data you or your third-party partners collect", and a third-party SDK is a third-party partner.
App Privacy has no IP address type, so decide whether that processing needs an entry, for example under Diagnostics.
The definitions are on https://developer.apple.com/app-store/app-privacy-details/ (read on 2026-10-02).

## Draft answers for Data safety (Play Console)

The same sources apply.
Data is encrypted in transit (HTTPS to Firebase).
The app gives no in-app way to request deletion, so answer the deletion question with the request method of the privacy policy, section 11.

| Data type                                  | Collected                   | Shared    | Optional                      | Purpose           |
| ------------------------------------------ | --------------------------- | --------- | ----------------------------- | ----------------- |
| Personal info: User IDs                    | Yes                         | No        | No: the app signs in at start | App functionality |
| Photos and videos: Photos                  | Yes                         | See below | Yes: only on a link share     | App functionality |
| App activity: Other user-generated content | Yes                         | See below | Yes: only on a link share     | App functionality |
| Location: Precise location                 | Yes until issue 20 is fixed | See below | Yes: only on a link share     | App functionality |

Google's guidance (https://support.google.com/googleplay/android-developer/answer/10787469, read on 2026-10-02) exempts from "sharing" a transfer "to a 'service provider' that processes it on behalf of the developer", which covers Firebase, and a transfer "based on a specific user-initiated action, where the user reasonably expects the data to be shared".
A report link is sent by the person, and the app tells the person at the first link of a client that anyone with the link can open the reports.
So "Shared: No" is defensible for the three rows, and the decision is yours.
The same page says to declare IP addresses by their use, "where developers use IP addresses as a means to determine location", which the app does not do.

## What the release builds checked

- `PrivacyInfo.xcprivacy`: see "Privacy manifest" below.
- `targetSdk`: see "Target SDK" below.
- `android/app/proguard-rules.pro`: see "R8 rules" below.

### Privacy manifest

The app target needs no `PrivacyInfo.xcprivacy` for a required-reason API, so this change adds none.

- Apple's rule: "If you use the API in your app's code, then you need to report the API in your app's privacy manifest file. If you use the API in your third-party SDK's code, then you need to report the API in your third-party SDK's privacy manifest file" (https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api, read on 2026-10-02).
- The code of the app: `ios/Runner/AppDelegate.swift` and `ios/Runner/SceneDelegate.swift` only register the plugins, and no file under `lib/` reads a file timestamp, the disk space, the boot time, or user defaults (grep for `stat`, `lastModified`, and `SharedPreferences`).
- The release build `build/ios/iphoneos/Runner.app` holds 31 `PrivacyInfo.xcprivacy` files: one for `Flutter.framework` and one for each SDK or plugin bundle that ships one. Together they declare FileTimestamp (`0A2A.1`, `C617.1`), SystemBootTime (`35F9.1`), and UserDefaults (`CA92.1`, `1C8F.1`, `C56D.1`): Flutter, gRPC, leveldb, and GoogleUtilities for the first two, and Firebase Auth, Firebase Core, GoogleUtilities, and GTMSessionFetcher for the third.
- The plugins and SDKs without a manifest (`firebase_core` 4.15.0, `firebase_auth` 6.7.0, `cloud_firestore` 6.10.0, `firebase_storage` 13.6.0, `printing` 5.15.1, the Firebase Storage SDK, and the interop packages) call none of these APIs in their source (grep of the pub cache and of `build/ios/SourcePackages/checkouts`).
- Limit: the static plugins and SDKs link into one `Runner` executable, which imports `stat` and `NSUserDefaults`. Without a link map, the call site of each symbol is inferred from the source greps above, not proven.
- The Firebase Auth, Firestore, and Installations manifests also declare collected data: User ID and Other Diagnostic Data. The Xcode privacy report of an archive adds them up, and App Store Connect compares it with the App Privacy answers, so the draft above lists both.

### Target SDK

The target SDK meets the Google Play minimum for a new app.

- Google Play: "New apps and app updates must target Android 16 (API level 36) or higher to be submitted to Google Play", from August 31, 2026 (https://developer.android.com/google/play/requirements/target-sdk, read on 2026-10-02).
- `android/app/build.gradle.kts` sets `targetSdk = flutter.targetSdkVersion`, and Flutter 3.47.5 sets it to 36 (`packages/flutter_tools/gradle/src/main/kotlin/FlutterExtension.kt`).
- The built bundle says the same: `base/manifest/AndroidManifest.xml` in `app-production-release.aab`, decoded with `protoc --decode_raw`, holds `targetSdkVersion` 36. Its `minSdkVersion` is 24, its `versionCode` 1, and its `versionName` 1.0.0.

### R8 rules

`android/app/build.gradle.kts` names `proguard-rules.pro` for the release build, and `android/app/proguard-rules.pro` does not exist.
The Gradle plugin skips the missing file: the R8 configuration of the release build (`build/app/outputs/mapping/productionRelease/configuration.txt`) lists the rules of the Flutter tool, of the Android default file, and of each library, and no `proguard-rules.pro`.
R8 ran and the bundle built, so the plugins and the Firebase SDKs keep what they need through their own consumer rules.
Whether the minified app runs was not checked: no device and no emulator ran it. Open the first internal testing build on a phone before you invite testers.
