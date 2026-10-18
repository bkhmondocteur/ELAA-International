import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:elaa_shared/elaa_shared.dart';
import 'dart:convert';
import 'doctor_dashboard.dart';

class ActivationScreen extends StatefulWidget {
  const ActivationScreen({super.key});

  @override
  State<ActivationScreen> createState() => _ActivationScreenState();
}

class _ActivationScreenState extends State<ActivationScreen> {
  final _licenceController = TextEditingController();
  final _pinController = TextEditingController();
  final _confirmPinController = TextEditingController();

  Future<void> _activateApp() async {
    final licence = _licenceController.text.trim();
    final pin = _pinController.text;
    final confirm = _confirmPinController.text;

    if (licence.isEmpty || pin.isEmpty || pin.length < 4) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Veuillez remplir tous les champs (PIN de 4 chiffres min).')));
      return;
    }
    if (pin != confirm) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Les codes PIN ne correspondent pas.')));
      return;
    }

    if (!licence.startsWith('ELAAMED-V2-')) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Clé de licence invalide pour ELAA DocPocket Med. Cette clé est probablement destinée à DocPocket Pro.')));
      return;
    }

    try {
      final query = await FirebaseFirestore.instance
          .collection('medecins')
          .where('licenceKey', isEqualTo: licence)
          .get();

      if (query.docs.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Clé de licence invalide ou introuvable.')));
        return;
      }

      final doc = query.docs.first;
      final medecin = Medecin.fromMap(doc.data(), doc.id);

      if (medecin.isLicenceExpired) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cette licence a expiré. Veuillez contacter l\'administration ELAA.')));
        return;
      }

      if (medecin.isMaxAppareilsReached) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Cette licence a atteint la limite d\'appareils autorisés (${medecin.maxAppareils}).')));
        return;
      }

      // 1. Générer RSA Key Pair
      final rsaPair = EncryptionEngine.generateRSAKeyPair();
      
      // Serialize Public Key
      final pubMap = {
        'modulus': rsaPair.publicKey.modulus.toString(),
        'exponent': rsaPair.publicKey.exponent.toString()
      };
      final pubBase64 = base64Encode(utf8.encode(jsonEncode(pubMap)));

      // Serialize Private Key
      final privMap = {
        'modulus': rsaPair.privateKey.modulus.toString(),
        'privateExponent': rsaPair.privateKey.privateExponent.toString(),
        'p': rsaPair.privateKey.p.toString(),
        'q': rsaPair.privateKey.q.toString(),
      };
      final privJson = jsonEncode(privMap);

      // 2. Dériver clé AES à partir du PIN
      final aesKey = EncryptionEngine.deriveKeyFromPin(pin, medecin.id);
      
      // 3. Chiffrer la clé privée avec la clé AES
      final encryptedPrivKey = EncryptionEngine.encryptDataAES(privJson, aesKey);

      // 4. Mettre à jour Firebase avec la clé publique et incrémenter le nombre d'appareils
      await FirebaseFirestore.instance.collection('medecins').doc(medecin.id).update({
        'publicKeyBase64': pubBase64,
        'statut': 'Actif',
        'nombreAppareilsActifs': medecin.nombreAppareilsActifs + 1,
      });

      // 5. Sauvegarder localement l'ID, le nom, le prénom et la clé privée chiffrée
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('medecin_id', medecin.id);
      await prefs.setString('medecin_nom', medecin.nom);
      await prefs.setString('medecin_prenom', medecin.prenom);
      await prefs.setString('encrypted_private_key', encryptedPrivKey);
      await prefs.setString('saved_pin', pin);
      await prefs.setString('saved_licence', licence);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Application activée avec succès !')));
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const DoctorDashboardScreen()));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Activation ELAA DocPocket Med')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.security, size: 64, color: Colors.teal),
                const SizedBox(height: 32),
                const Text('Bienvenue Docteur', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                const Text('Veuillez entrer la clé de licence qui vous a été transmise par le Hub ELAA, ainsi qu\'un code PIN personnel (4 à 6 chiffres) qui protégera vos dossiers médicaux.'),
                const SizedBox(height: 32),
                TextField(
                  controller: _licenceController,
                  decoration: const InputDecoration(labelText: 'Clé de licence (ex: ABCD-1234)', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _pinController,
                  decoration: const InputDecoration(labelText: 'Nouveau Code PIN', border: OutlineInputBorder()),
                  obscureText: true,
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _confirmPinController,
                  decoration: const InputDecoration(labelText: 'Confirmez le Code PIN', border: OutlineInputBorder()),
                  obscureText: true,
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 32),
                ElevatedButton(
                  onPressed: _activateApp,
                  style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                  child: const Text('Activer l\'application'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
