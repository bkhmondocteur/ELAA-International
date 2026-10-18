import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'screens/dashboard_screen.dart';
import 'hub_security_manager.dart';

import 'package:cloud_firestore/cloud_firestore.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: false,
  );
  runApp(const ElaaDocPocketHub());
  HubSecurityManager.initializeKeys();
}

class ElaaDocPocketHub extends StatelessWidget {
  const ElaaDocPocketHub({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ELAA DocPocket Pro Hub Opérateur',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0284C7)), // Blue Medical
        useMaterial3: true,
        textTheme: ThemeData.light().textTheme.apply(
          bodyColor: Colors.black,
          displayColor: Colors.black,
        ),
        inputDecorationTheme: const InputDecorationTheme(
          labelStyle: TextStyle(color: Colors.black87),
        ),
      ),
      home: const DashboardScreen(),
    );
  }
}

