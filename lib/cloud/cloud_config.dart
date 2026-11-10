import 'package:firebase_core/firebase_core.dart';

/// Public Firebase app identifiers, supplied by the developer at build time.
/// Never put service-account keys or passwords in a mobile application.
class CloudConfig {
  static const apiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const appId = String.fromEnvironment('FIREBASE_APP_ID');
  static const projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
  static const senderId = String.fromEnvironment(
    'FIREBASE_MESSAGING_SENDER_ID',
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
