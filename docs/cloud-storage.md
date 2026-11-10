# Cloud storage foundation

This branch adds an opt-in cloud entry point without uploading the demo data.

## Current connected flow

The default `lib/main.dart` now opens the signed-in cloud app. Run:

```powershell
flutter run --dart-define-from-file=firebase-config.local.json
```

The old temporary-data demo is available separately with `flutter run -t lib/main_demo.dart`.
The local Android Studio main.dart configuration includes the Firebase build arguments.

After signing in, tap a group to view spending, per-member balances, and expenses.
Add expenses with a payer and selected group participants. Equal splits distribute leftover
cents by sorted member ID, so balances always conserve the total. Amounts use USD cents.
Expense documents live in `groups/{groupId}/expenses`; balances are derived from the
live expense stream, rather than storing independently mutable totals.

**Publish the updated `firestore.rules` before using expenses.** Existing deployed rules
from the first milestone deny all expense reads and writes. Copy this file into the
Firestore Rules editor and publish, or deploy it with the Firebase CLI. No live rules
were deployed automatically in this session.

A one-member group records spending with zero shared debt. Invitations, member names,
repayments, editing/deleting expenses, receipt upload, and shared goals remain future work.
The UI uses “Member 2” etc. for other existing account IDs until profiles are implemented.

## Implemented

- Email/password registration and sign-in through Firebase Authentication; the SDK restores the session on future launches.
- Firestore group creation and live member-filtered queries, using stable user IDs.
- Cached/pending-write status. Firestore provides persistent offline caching by default on Android. Initial registration/sign-in needs internet. A write may remain pending until the server confirms it.
- Rules permit authenticated users to create groups containing only themselves and read only their groups. Other writes and collections are denied.
- Default cloud (`lib/main.dart`, also `lib/main_cloud.dart`) and optional demo (`lib/main_demo.dart`) entry points.

Goals, invitations, account deletion, and password reset are not implemented yet. Creating a group does not invite anyone. Group edits and membership changes are intentionally denied until a trusted invitation flow is implemented. The cloud view starts empty; sample financial data is never uploaded.

## One-time developer setup

1. Create/select a Firebase project. Register an Android app matching the Android application ID (currently `com.example.app6`; choose the final package ID before publication).
2. Enable Authentication > Email/Password.
3. Create the default Cloud Firestore database in production mode and choose its region.
4. Copy `firebase-config.example.json` to `firebase-config.local.json`. Fill the public identifiers from that registered Android app: API key, app ID, project ID, and messaging sender ID (project number). These values are Firebase client identifiers, not service-account credentials. Never embed a service-account private key.
5. Install/sign into the Firebase CLI, then deploy the checked-in rules to the intended project:

   ```powershell
   firebase deploy --only firestore:rules --project YOUR_PROJECT_ID
   ```

6. Run the cloud entry point:

   ```powershell
   flutter run -t lib/main_cloud.dart --dart-define-from-file=firebase-config.local.json
   ```

The app initializes Firebase explicitly from Dart options; this email/password + Firestore milestone does not use Google Sign-In or Analytics. If using FlutterFire CLI later, its generated `DefaultFirebaseOptions.currentPlatform` can replace `CloudConfig.options`. Use platform-specific configuration when adding another platform.

The installed app contains these settings. Members never run these commands: they open the app and sign in.

## Verification before enabling real users

Local automated tests cover group record parsing, streamed UI updates, failed writes/retry, missing setup UI, and the existing demo. They do not connect to a real Firebase service or prove server rules enforcement.

Against an isolated Firebase test project (or configured Auth/Firestore emulators), verify:

- User A creates a group; signing into A on a second device loads the same group automatically.
- User B cannot read A's group, add themselves to it, or forge its owner. Unauthenticated reads/writes fail.
- Invalid group schemas, extra fields, and membership updates are rejected by rules.
- After loading a group, restart offline to verify Android caching. Create offline, reconnect, and verify one group is saved with no duplicate.
- Sign out and sign in as B; A's groups must not appear in B's member-filtered view.

Do not treat this branch as production-ready until these integration checks and the remaining membership/expense workflows are complete.

## Next milestone

Add secure invitations and real member profiles, then repayments, expense editing, and receipts. Expenses are now separate documents under `groups/{groupId}/expenses` to avoid overwriting an entire group history during concurrent changes.

References: https://firebase.google.com/docs/flutter/setup and https://firebase.google.com/docs/firestore/manage-data/enable-offline
