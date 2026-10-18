import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'screens/activation_screen.dart';
import 'screens/doctor_dashboard.dart';
import 'screens/pin_login_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: false,
  );
  final prefs = await SharedPreferences.getInstance();
  String? medecinId = prefs.getString('medecin_id');
  final savedLicence = prefs.getString('saved_licence');

  if (medecinId == null && savedLicence != null && savedLicence.isNotEmpty) {
    try {
      final query = await FirebaseFirestore.instance
          .collection('medecins')
          .where('licenceKey', isEqualTo: savedLicence)
          .limit(1)
          .get();
      if (query.docs.isNotEmpty) {
        final doc = query.docs.first;
        medecinId = doc.id;
        await prefs.setString('medecin_id', medecinId!);
        await prefs.setString('medecin_nom', doc.data()['nom'] ?? '');
        await prefs.setString('medecin_prenom', doc.data()['prenom'] ?? '');
      }
    } catch (_) {}
  }

  if (medecinId == null) {
    try {
      var query = await FirebaseFirestore.instance
          .collection('medecins')
          .where('statut', isEqualTo: 'Actif')
          .limit(1)
          .get();
      if (query.docs.isEmpty) {
        query = await FirebaseFirestore.instance.collection('medecins').limit(1).get();
      }
      if (query.docs.isNotEmpty) {
        final doc = query.docs.first;
        medecinId = doc.id;
        await prefs.setString('medecin_id', medecinId!);
        await prefs.setString('medecin_nom', doc.data()['nom'] ?? '');
        await prefs.setString('medecin_prenom', doc.data()['prenom'] ?? '');
      }
    } catch (_) {}
  }

  runApp(ElaaDocPocketMed(initialMedecinId: medecinId));
}

class ElaaDocPocketMed extends StatelessWidget {
  final String? initialMedecinId;
  const ElaaDocPocketMed({super.key, this.initialMedecinId});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ELAA DocPocket Med',
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
      home: (initialMedecinId != null && initialMedecinId!.isNotEmpty)
          ? PinLoginScreen(medecinId: initialMedecinId!)
          : const ActivationScreen(),
    );
  }
}

