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
  final bool explicitlyChosen = prefs.getBool('doctor_explicitly_chosen') ?? false;
  final savedLicence = prefs.getString('saved_licence');

  // Check URL parameter first (e.g. ?medecin=Hamed or ?id=...)
  final urlMed = Uri.base.queryParameters['medecin']?.toLowerCase();

  if (urlMed != null) {
    try {
      final snap = await FirebaseFirestore.instance.collection('medecins').get();
      final match = snap.docs.firstWhere(
        (d) => (d.data()['nom']?.toString().toLowerCase().contains(urlMed) == true) ||
               (d.data()['prenom']?.toString().toLowerCase().contains(urlMed) == true) ||
               d.id.toLowerCase() == urlMed,
      );
      medecinId = match.id;
      await prefs.setString('medecin_id', medecinId);
      await prefs.setString('medecin_nom', match.data()['nom'] ?? '');
      await prefs.setString('medecin_prenom', match.data()['prenom'] ?? '');
      await prefs.setBool('doctor_explicitly_chosen', true);
    } catch (_) {}
  } else if (medecinId == null && savedLicence != null && savedLicence.isNotEmpty) {
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

  if (!explicitlyChosen || medecinId == null) {
    try {
      final snap = await FirebaseFirestore.instance.collection('medecins').get();
      if (snap.docs.isNotEmpty) {
        final hamedDoc = snap.docs.firstWhere(
          (d) => (d.data()['nom']?.toString().toUpperCase().contains('BEN KHALIFA') == true) ||
                 (d.data()['prenom']?.toString().toLowerCase().contains('hamed') == true),
          orElse: () => snap.docs.firstWhere(
            (d) => d.data()['statut'] == 'Actif',
            orElse: () => snap.docs.first,
          ),
        );
        medecinId = hamedDoc.id;
        await prefs.setString('medecin_id', medecinId);
        await prefs.setString('medecin_nom', hamedDoc.data()['nom'] ?? '');
        await prefs.setString('medecin_prenom', hamedDoc.data()['prenom'] ?? '');
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

