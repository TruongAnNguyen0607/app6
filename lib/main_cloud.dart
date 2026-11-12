import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'cloud/cloud_config.dart';
import 'cloud/cloud_home.dart';
import 'cloud/group_repository.dart';
import 'cloud/invitation_repository.dart';
import 'cloud/expense_repository.dart';
import 'demo_app.dart' show MyApp;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Widget home;
  if (!CloudConfig.isConfigured) {
    home = const CloudSetupMessage(
      message: 'Cloud setup is not complete for this build. The developer needs to connect a Firebase project.',
    );
  } else {
    try {
      await Firebase.initializeApp(options: CloudConfig.options);
      home = CloudAuthGate(
        auth: FirebaseAuth.instance,
        invitations: FirestoreInvitationRepository(FirebaseFirestore.instance),
        repository: FirestoreGroupRepository(FirebaseFirestore.instance),
        expenseRepository: FirestoreExpenseRepository(
          FirebaseFirestore.instance,
        ),
      );
    } catch (_) {
      home = const CloudSetupMessage(
        message: 'Could not connect to the cloud service. Check your connection and reopen the app. If this continues, contact the developer.',
      );
    }
  }
  runApp(MyApp(home: home));
}

class CloudSetupMessage extends StatelessWidget {
  const CloudSetupMessage({super.key, required this.message});
  final String message;
  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_outlined, size: 48),
              const SizedBox(height: 20),
              Text(
                'Together cloud',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 16),
              Text(message, textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    ),
  );
}
