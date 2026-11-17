import 'package:firebase_core/firebase_core.dart';

/// Public Firebase app identifiers, supplied by the developer at build time.
/// Never put service-account keys or passwords in a mobile application.
class CloudConfig {
  static const apiKey = String.fromEnvironment(
    'FIREBASE_API_KEY',
    defaultValue: 'AIzaSyDXC6_XU6s7_J7mI-jgoQVBNmXiUo8r7uk',
  );
  static const appId = String.fromEnvironment(
    'FIREBASE_APP_ID',
    defaultValue: '1:118314016873:android:0a33cfbd1adde8e6c4c2f8',
  );
  static const projectId = String.fromEnvironment(
    'FIREBASE_PROJECT_ID',
    defaultValue: 'together-8f74b',
  );
  static const senderId = String.fromEnvironment(
    'FIREBASE_MESSAGING_SENDER_ID',
    defaultValue: '118314016873',
  );

  static bool get isConfigured =>
      [apiKey, appId, projectId, senderId].every((value) => value.isNotEmpty);

  static FirebaseOptions get options => FirebaseOptions(
    apiKey: apiKey,
    appId: appId,
    projectId: projectId,
    messagingSenderId: senderId,
  );
}
