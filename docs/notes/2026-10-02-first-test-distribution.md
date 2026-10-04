# First test distribution: console steps

This note lists what the operator does outside the repository before the first TestFlight build and the first Google Play internal testing release of version `1.0.0` build `1`.
The brief is `docs/plans/2026-10-02-release-prep.md`.
Nothing in this list was done by an agent: no store record, no upload, no signing with a real key.
The deploys of the rules and Hosting are the one exception, made with the operator's approval, and `CLAUDE.md` owns their state.

## Open items before an external TestFlight review

The TestFlight overview says: "When you add the first build of your app to a group, the build gets sent to App Review …" (https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview, read on 2026-10-02), and these items can block that review.
The same page allows up to 100 internal testers per app, who are App Store Connect users with access to it.

1. **Account deletion (App Store Review Guideline 5.1.1(v)).** Closed by the brief `docs/plans/2026-10-02-account-deletion.md`: the company profile screen has a "delete all data" control, which deletes the published photos, reports, and client pages, the anonymous account, and the data on the phone. Pull request 19 quotes Apple's text under "Account deletion".
2. **Photo location (issue 20).** Closed by pull request 23: `withoutLocation` removes the location when a photo is stored, before an upload, and before the PDF, on every platform. No device ran it. An object that a build before pull request 23 uploaded keeps its location in Storage.
3. **Anonymous account clean-up (issue 21).** Closed: the operator turned the automatic clean-up off on 2026-10-02, and the privacy pages no longer say that an account is deleted after 30 days. Firebase documents that an account that was already scheduled for deletion when the clean-up was turned off stays scheduled (https://firebase.google.com/docs/auth/android/anonymous-auth, "Automatic clean-up").
4. **Support contact.** `support_url.txt` names the landing page `https://kkomkkomi.web.app/`, which has no working contact: its inquiry form is a preview that sends nothing. Guideline 1.5 says: "Make sure your app and its Support URL include an easy way to contact you". Add a contact to that page, or give another support URL.
5. **Privacy policy.** The pages at `/privacy/` and `/privacy/en/` are live since the Hosting deploy from `34d5d23`, and no placeholder of pull request 19 is left in them. Four clauses are agent defaults that a qualified person should review: the legal basis of the transfer abroad (Article 28-8(1)3 of the Personal Information Protection Act), the cleaning company as the party responsible for the people in the photos, the Firebase support URL as the contact of Google, and the effective date, which is the merge date of the last change to the pages (2026-10-05, the pull request of `docs/plans/2026-10-05-m3-02-entitlements-port.md`, which adds the Purchase History of the RevenueCat manifest to section 10).

## Values

| Item                           | Value                                                                                            |
| ------------------------------ | ------------------------------------------------------------------------------------------------ |
| Bundle ID and application ID   | `kr.donminzzi.kkomkkomi` (production flavor)                                                     |
| Version                        | `1.0.0`, build `1`, from `pubspec.yaml`                                                          |
| iOS minimum version            | 15.0 (`IPHONEOS_DEPLOYMENT_TARGET`)                                                              |
| iOS devices                    | iPhone only (`TARGETED_DEVICE_FAMILY = 1` in the Runner target, operator decision of 2026-10-04) |
| Android minimum and target SDK | 24 and 36, read from the built bundle                                                            |
| Privacy policy                 | `https://kkomkkomi.web.app/privacy/` (Korean), `https://kkomkkomi.web.app/privacy/en/` (English) |
| App Store categories           | Business, then Productivity (`fastlane/metadata/ios/*_category.txt`)                             |

`DEVELOPMENT_TEAM` is `393JTTV68D` in each of the nine build configurations of the Runner target in `ios/Runner.xcodeproj` (operator, 2026-10-02), so a signed build needs no manual team choice.

## Apple

1. **Bundle ID.** In Certificates, Identifiers & Profiles, register the explicit App ID `kr.donminzzi.kkomkkomi`. The app uses no capability that needs a switch there: no push notification, no sign in with Apple, no app group.
2. **App Store Connect app record.** Create a new iOS app with the bundle ID above, the primary language Korean, the name from `fastlane/metadata/ios/ko/name.txt`, and an SKU of your choice. The operator chose that name on 2026-10-04, after finding that an app named 꼼꼬미 already exists.
3. **App information.** Set the category, the privacy policy URL, and the content rights. Answer the age rating questions. In Pricing and Availability, make the app free: the operator decided on 2026-10-04 that the app is free to download and that the paid plans are in-app subscriptions (M3, issue 36).
4. **Export compliance.** Decided by the operator on 2026-10-04: `ios/Runner/Info.plist` declares `ITSAppUsesNonExemptEncryption` as `NO`, because no code under `lib/` or `ios/Runner/` encrypts anything and the Firebase SDKs use HTTPS. The build bundles the `openssl_grpc` framework of gRPC.
5. **App Store Connect API key.** In Users and Access, Integrations, generate a team API key whose role can upload builds and edit the app information. Keep the `.p8` file outside the repository, and set the three `APP_STORE_CONNECT_API_KEY_*` variables that the "Release" section of `CLAUDE.md` names.
6. **Build and upload.** Run `merry run release ios`, which checks, builds, and uploads the IPA to TestFlight; the "Release" section of `CLAUDE.md` owns the scripts. The build needs `ios/Runner/GoogleService-Info.plist` from `flutterfire configure`, as `CLAUDE.md` says. `merry run release metadata ios` uploads the store texts of `fastlane/metadata/ios` without a binary and without a review submission.
7. **TestFlight.** Make an internal group and add the testers. `merry run release ios` uploads the build without waiting for processing and adds it to no group (`skip_waiting_for_build_processing: true` and no `groups` in the `beta` lane of `fastlane/Fastfile`). Apple's page "Add internal testers" says: "If automatic distribution isn't enabled, you must manually add all builds to the group" (https://developer.apple.com/help/app-store-connect/test-a-beta-version/add-internal-testers, read on 2026-10-04). So when processing is done, open the group in the TestFlight tab, click Add Builds, choose build 1, click Next, paste the "What to Test" text below, and click Add. The same page describes the checkbox as Xcode delivery: "To enable Xcode to automatically deliver builds to all group members, select the "Enable automatic distribution" checkbox", and the lane uploads through fastlane, not Xcode, so check that build 1 shows in the group before the testers start. For an external group, settle the open items above first.
8. **App Privacy.** Enter the answers in "Draft answers for App Privacy" below.

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

1. **Play Console app.** Create the app with the default language Korean (`ko-KR`), the name from `fastlane/metadata/android/ko-KR/title.txt`, the type App, and Free (operator decision, 2026-10-04; the paid plans are in-app subscriptions, M3, issue 36). The choice is final: "Once your app has been offered for free, the app can't be changed to paid" (Play Console Help, "Set up your app's prices", https://support.google.com/googleplay/android-developer/answer/6334373, read on 2026-10-04).
2. **Store settings.** Choose the category Business, and enter the contact details.
3. **App content.** Enter the privacy policy URL. For app access, all functions work without a login. Ads: none. Answer the content rating questions and the target audience. Enter the Data safety answers below.
4. **Internal testing track, first bundle by hand.** Build the first App Bundle with `merry run build aab`, create a release on the internal testing track in Play Console, upload the bundle there, add the testers' email list, and use `fastlane/metadata/android/<locale>/changelogs/1.txt` as the release notes. `supply` cannot make the first upload: "Before using _supply_ to connect to Google Play Store, you'll need to set up your app manually first by uploading at least one build to Google Play Store" (https://docs.fastlane.tools/actions/supply/, "Quick Start"; the same text is in the documentation of fastlane 2.240.1, which `Gemfile.lock` pins).
5. **App signing.** Play App Signing keeps the key that signs the app for users. The bundle that you upload is signed with your upload key.
6. **Service account.** Make a Google Cloud service account and a JSON key for it, as the "Setup" section of the same page describes, and invite the service account in Play Console with the permission to release the app. Keep the key outside the repository and set `SUPPLY_JSON_KEY` to its path.
7. **Later builds.** Run `merry run release android`, which checks, builds, and uploads the bundle with its changelogs to the internal testing track. By default the release is a draft, which Google Play requires while the app is a draft in Play Console, and it goes to the testers when you roll it out there; `SUPPLY_RELEASE_STATUS=completed` rolls it out at upload (the "Release" section of `CLAUDE.md`). `merry run release metadata android` uploads the store texts and images of `fastlane/metadata/android` without a bundle.

### The upload key

- Make it once with `keytool -genkeypair` (RSA 2048, a long validity) and keep the keystore and its passwords outside the repository, with a backup. The root `.gitignore` ignores `*.jks` in every directory, and `android/.gitignore` ignores `*.keystore` and `key.properties` under `android/` only, so a keystore or a `key.properties` at the root of the repository is not ignored.
- `android/app/build.gradle.kts` reads it from the four variables `ANDROID_KEYSTORE_PATH`, `ANDROID_KEYSTORE_ALIAS`, `ANDROID_KEYSTORE_PASSWORD`, and `ANDROID_KEYSTORE_PRIVATE_KEY_PASSWORD`, or from `android/key.properties` when `ANDROID_KEYSTORE_PATH` is not set.
- `merry run build aab` (the first bundle) and `merry run release android` (each later bundle) build `build/app/outputs/bundle/productionRelease/app-production-release.aab` with that key. The bundle needs `android/app/google-services.json` from `flutterfire configure`.
- Play Console Help says: "If you lose your upload key or suspect that it was compromised, you are not locked out of your app", and a new upload key is then registered through a reset request (https://support.google.com/googleplay/android-developer/answer/9842756, read on 2026-10-02). The same page says that a new app is enrolled in Play App Signing with keys that Google generates.

## Firebase

- The Firebase macOS app is registered as `com.example.myApp` (the `BUNDLE_ID` of `macos/Runner/GoogleService-Info.plist` in the operator's checkout), and the macOS production bundle ID is now `kr.donminzzi.kkomkkomi`. macOS is not a target, so this needs no action now. Before a macOS production build, register the macOS app again and run `flutterfire configure`.
- Hosting serves the privacy policy URLs since the deploy from `34d5d23`, so a store listing can name them. A later deploy needs your approval again.

## Subscriptions (M3, issue 36)

- **The RevenueCat keys.** Before a release build, create `config/revenuecat.json` from `config/revenuecat.example.json` and fill in the public SDK keys of the RevenueCat iOS and Android apps. The "Release" section of `CLAUDE.md` owns what the build and the release check do with the file.
- **Play Billing Library before the Play products.** Android's "Getting ready" page says: "Once you've set up a developer account, you must publish a version of your app that includes the Google Play Billing Library. This step is required to enable billing-related features in the Google Play Console, such as configuring the products you want to sell" (https://developer.android.com/google/play/billing/getting-ready, read on 2026-10-05). `purchases_flutter` brings that library into the Android build, so upload a bundle of a build with it before you create the subscriptions in Play Console. Assumption, not a fact: a release that is rolled out on the internal testing track counts as publishing for this step. The page does not say which tracks count, so check it in Play Console when the subscriptions are created.

## Draft answers for App Privacy (App Store Connect)

Sources: `lib/firebase/firebase_publisher.dart` (what a link share uploads), `lib/firebase/firebase_identity.dart` (anonymous sign-in), the privacy policy pages of pull request 19, and Google's list of the data that each Firebase SDK collects (https://firebase.google.com/docs/android/play-data-disclosure, read on 2026-10-02).
The app sends nothing before the person taps the link share, except the anonymous sign-in at start.
No data is used for tracking, and no data goes to an ad network or a data broker.

| Data type                          | Collected | Linked to the user | Purpose           | Why                                                                                                                                                     |
| ---------------------------------- | --------- | ------------------ | ----------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Identifiers: User ID               | Yes       | Yes                | App Functionality | The anonymous Firebase user ID owns each client page (`ownerUid`).                                                                                      |
| User Content: Photos or Videos     | Yes       | Yes                | App Functionality | A link share uploads the before and after photos of the visit.                                                                                          |
| User Content: Other User Content   | Yes       | Yes                | App Functionality | A link share uploads the company name, the client name, the zone names, the notes, and the visit date.                                                  |
| Location: Precise Location         | No        | -                  | -                 | The app removes the location of a photo before it stores or uploads the photo (issue 20, pull request 23), and it asks for no location permission.      |
| Diagnostics: Other Diagnostic Data | Yes       | No                 | Analytics         | The Firebase Auth, Firestore, and Installations privacy manifests declare it as not linked, not tracking, for Analytics (see "Privacy manifest" below). |
| Purchases: Purchase History        | Yes       | No                 | App Functionality | The RevenueCat privacy manifest declares it as not linked, not tracking, for App Functionality (see "Privacy manifest" below).                          |

Firebase Authentication also processes the IP address and the user agent of each sign-in for security and abuse prevention.
Apple's page says: "You need to identify all of the data you or your third-party partners collect …", and a third-party SDK is a third-party partner.
For the IP address it says: "Declare the relevant data types based on how you use IP address, such as precise location, coarse location, device ID, or diagnostics."
The definitions are on https://developer.apple.com/app-store/app-privacy-details/ (read on 2026-10-02).

The Diagnostics row is declared, as the Firebase manifests declare it (operator decision, 2026-10-02).
The Purchase History row follows the RevenueCat manifest in the same way.
Section 10 of the privacy policy names that data as the manifests declare it (Other Diagnostic Data, not linked to the user, not for tracking, for Analytics, in the Auth, Firestore, and Installations manifests of firebase-ios-sdk 12.19.0), and gives the example that Google's list names for Auth and Firestore: the Firebase user agent (device, OS version, SDK versions).
It also names the Purchase History that the manifest of the RevenueCat iOS SDK 5.92.0 declares (not linked to the user, not for tracking, for App Functionality), and says that the app version sells no subscription and sends nothing to RevenueCat.

## Draft answers for Data safety (Play Console)

The same sources apply.
Data is encrypted in transit (HTTPS to Firebase).
Deletion: the company profile screen deletes the account and all its data in the app, and the tracked privacy policy names the email of the privacy officer as the way to ask outside the app.
The privacy policy is deployed, so the store answer is pending on one step: the operator's confirmation of the deletion path outside the app in Play Console.
Until it is done, Google's account deletion requirement stays open; pull request 19 leaves it unresolved for an account that the app makes without an action of the person.

| Data type                                  | Collected              | Shared    | Optional                      | Purpose           |
| ------------------------------------------ | ---------------------- | --------- | ----------------------------- | ----------------- |
| Personal info: User IDs                    | Yes                    | See below | No: the app signs in at start | App functionality |
| Photos and videos: Photos                  | Yes                    | See below | Yes: only on a link share     | App functionality |
| App activity: Other user-generated content | Yes                    | See below | Yes: only on a link share     | App functionality |
| Location: Precise location                 | No (issue 20 is fixed) | -         | -                             | -                 |

Google's guidance (https://support.google.com/googleplay/android-developer/answer/10787469, read on 2026-10-02) exempts from "sharing" a transfer "to a 'service provider' that processes it on behalf of the developer", which covers Firebase, and a transfer "based on a specific user-initiated action, where the user reasonably expects the data to be shared".
A report link is sent by the person, and the app tells the person at the first link of a client that anyone with the link can open the reports.
Anyone with the link can also read the user ID, because the page document holds it as `ownerUid` (`firestore.rules`).
So "Shared: No" is defensible for the three rows that are collected, and the decision is yours.
The same page says to declare IP addresses by their use, "where developers use IP addresses as a means to determine location", which the app does not do.

## What the release builds checked

- `PrivacyInfo.xcprivacy`: see "Privacy manifest" below.
- `targetSdk`: see "Target SDK" below.
- `android/app/proguard-rules.pro`: see "R8 rules" below.
- The flow on a phone: see "Device check" below.

### Privacy manifest

The app target needs no `PrivacyInfo.xcprivacy` for a required-reason API, so this change adds none.

- Apple's rule: "If you use the API in your app's code, then you need to report the API in your app's privacy manifest file. If you use the API in your third-party SDK's code, then you need to report the API in your third-party SDK's privacy manifest file" (https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api, read on 2026-10-02).
- The code of the app: `ios/Runner/AppDelegate.swift` and `ios/Runner/SceneDelegate.swift` only register the plugins, and no file under `lib/` reads a file timestamp, the disk space, the boot time, or user defaults (grep for `stat`, `lastModified`, and `SharedPreferences`).
- The release build `build/ios/iphoneos/Runner.app` holds 31 `PrivacyInfo.xcprivacy` files: one for `Flutter.framework` and one for each SDK or plugin bundle that ships one. Together they declare FileTimestamp (`0A2A.1`, `C617.1`) in Flutter, gRPC, leveldb, and GoogleUtilities, SystemBootTime (`35F9.1`) in Flutter and gRPC, and UserDefaults (`CA92.1`, `1C8F.1`, `C56D.1`) in Firebase Auth, Firebase Core, Firebase Core Internal, GoogleUtilities, and GTMSessionFetcher.
- The plugins and SDKs without a manifest (`firebase_core` 4.15.0, `firebase_auth` 6.7.0, `cloud_firestore` 6.10.0, `firebase_storage` 13.6.0, `printing` 5.15.1, the Firebase Storage SDK, and the interop packages) call none of these APIs in their source (grep of the pub cache and of `build/ios/SourcePackages/checkouts`).
- Limit: the static plugins and SDKs link into one `Runner` executable, which imports `stat` and `NSUserDefaults`. Without a link map, the call site of each symbol is inferred from the source greps above, not proven.
- The Firebase Auth, Firestore, and Installations manifests also declare collected data: User ID and Other Diagnostic Data. The draft above lists both, so that the answers match what the bundled SDKs declare.
- `purchases_flutter` 10.14.0 depends on `purchases-hybrid-common` 19.5.0, which depends on the RevenueCat iOS SDK 5.92.0 (the `Package.swift` of each, read on 2026-10-05). The manifest of that SDK declares UserDefaults (`CA92.1`) and the collected data Purchase History, not linked, not tracking, for App Functionality (https://raw.githubusercontent.com/RevenueCat/purchases-ios/5.92.0/Sources/PrivacyInfo.xcprivacy, read on 2026-10-05). The manifest of `purchases-hybrid-common` declares UserDefaults (`CA92.1`) and no collected data. No release build with these SDKs was made yet, so the count of manifests above predates them.

### Target SDK

The target SDK meets the Google Play minimum for a new app.

- Google Play: "New apps and app updates must target Android 16 (API level 36) or higher to be submitted to Google Play", from August 31, 2026 (https://developer.android.com/google/play/requirements/target-sdk, read on 2026-10-02).
- `android/app/build.gradle.kts` sets `targetSdk = flutter.targetSdkVersion`, and Flutter 3.47.5 sets it to 36 (`packages/flutter_tools/gradle/src/main/kotlin/FlutterExtension.kt`).
- The built bundle says the same: `base/manifest/AndroidManifest.xml` in `app-production-release.aab`, decoded with `protoc --decode_raw`, holds `targetSdkVersion` 36. Its `minSdkVersion` is 24, its `versionCode` 1, and its `versionName` 1.0.0.

### R8 rules

`android/app/build.gradle.kts` names `proguard-rules.pro` for the release build. The release build of pull request 22 ran before the file existed, and the Gradle plugin skipped it: the R8 configuration of that build (`build/app/outputs/mapping/productionRelease/configuration.txt`) listed the rules of the Flutter tool, of the Android default file, and of each library.
`android/app/proguard-rules.pro` now exists with a comment and no rule, and it names the consumer rules that R8 already applies.
R8 ran with the consumer rules of the plugins and the Firebase SDKs, and the bundle built.
Whether the minified app runs was not checked: no device and no emulator ran it. Open the first internal testing build on a phone before you invite testers.

### Device check

On 2026-10-03 the operator ran an iOS release build of the production flavor on an iPhone, from a commit that has the client link screen (`bc4d57c` or later), and every step passed:

1. take the photos of a visit;
2. share the report as a link;
3. open the web report;
4. close the link from the client screen ("링크 막기");
5. the web report no longer opens;
6. make a new link and share it again;
7. delete all data from the company profile screen: the client list is empty, and the new link no longer opens.

This is the first run of Firebase start, anonymous sign-in, the upload, the web report, the revoke, the reissue, and the deletion on a device; the automated tests replace Firebase with fakes.
No Android build has run on a device, so the R8 item above stays open.
