# Together

A Flutter group expense tracker using Firebase Authentication and Firestore.

## Run on Android

The repository includes `firebase-config.android.json`, the public Firebase client
configuration for the shared `together-8f74b` project.

Start an Android emulator or connect an Android phone, then run from this folder:

```powershell
flutter pub get
flutter run --dart-define-from-file=firebase-config.android.json
```

Select the Android device if prompted. In Android Studio, add
`--dart-define-from-file=firebase-config.android.json` to the Flutter run
configuration's additional arguments.

This configuration is for Android. To run in Chrome, first register a Web app in
the same Firebase project and supply its own Firebase client configuration.

Client settings identify the Firebase project; access to group data is controlled
by authentication and Firestore rules. Never add service-account keys or passwords
to these configuration files. `firebase-config.local.json` remains ignored for
developer overrides.

See [cloud setup and invitations](docs/cloud-storage.md) for more details.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
