import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:elaa_shared/crypto/encryption_engine.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'doctor_dashboard.dart';
import 'activation_screen.dart';

class PinLoginScreen extends StatefulWidget {
  final String medecinId;
  const PinLoginScreen({super.key, required this.medecinId});

  @override
  State<PinLoginScreen> createState() => _PinLoginScreenState();
}

class _PinLoginScreenState extends State<PinLoginScreen> {
  final _pinController = TextEditingController();
  String _medecinNom = '';
  String _medecinPrenom = '';
  String? _savedPin;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadDoctorInfo();
  }

  Future<void> _loadDoctorInfo() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _medecinNom = prefs.getString('medecin_nom') ?? '';
      _medecinPrenom = prefs.getString('medecin_prenom') ?? '';
      _savedPin = prefs.getString('saved_pin');
      _isLoading = false;
    });
  }

  Future<void> _applyPinAndGenerateKeys(String newPin) async {
    final prefs = await SharedPreferences.getInstance();
    final rsaPair = EncryptionEngine.generateRSAKeyPair();

    final pubMap = {
      'modulus': rsaPair.publicKey.modulus.toString(),
      'exponent': rsaPair.publicKey.exponent.toString(),
    };
    final pubBase64 = base64Encode(utf8.encode(jsonEncode(pubMap)));

    final privMap = {
      'modulus': rsaPair.privateKey.modulus.toString(),
      'privateExponent': rsaPair.privateKey.privateExponent.toString(),
      'p': rsaPair.privateKey.p.toString(),
      'q': rsaPair.privateKey.q.toString(),
    };
    final privJson = jsonEncode(privMap);

    final aesKey = EncryptionEngine.deriveKeyFromPin(newPin, widget.medecinId);
    final encryptedPrivKey = EncryptionEngine.encryptDataAES(privJson, aesKey);

    try {
      await FirebaseFirestore.instance.collection('medecins').doc(widget.medecinId).update({
        'publicKeyBase64': pubBase64,
        'dateMiseAJourCle': FieldValue.serverTimestamp(),
      });
    } catch (_) {}

    await prefs.setString('encrypted_private_key', encryptedPrivKey);
    await prefs.setString('saved_pin', newPin);
    _savedPin = newPin;
  }

  Future<void> _unlockApp() async {
    final inputPin = _pinController.text.trim();
    if (inputPin.isEmpty || inputPin.length < 4) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Veuillez entrer votre code PIN (4 chiffres minimum).')),
      );
      return;
    }
    // Accept if matches saved PIN or is universal code 1234
    if (inputPin == _savedPin || inputPin == '1234' || _savedPin == null || _savedPin!.isEmpty) {
      if (inputPin == '1234' && _savedPin != '1234') {
        await _applyPinAndGenerateKeys('1234');
      } else if (_savedPin == null || _savedPin!.isEmpty) {
        await _applyPinAndGenerateKeys(inputPin);
      }
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const DoctorDashboardScreen()),
      );
      return;
    }

    _pinController.clear();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Code PIN incorrect. Vous pouvez utiliser 1234 ou cliquer sur "Définir à 1234".'),
        backgroundColor: Colors.redAccent,
      ),
    );
  }

  Future<void> _resetLicence() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Changer de licence ?'),
        content: const Text(
          'Voulez-vous vous déconnecter et réinitialiser la clé de licence sur cet appareil ?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Réinitialiser'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('medecin_id');
      await prefs.remove('saved_pin');
      await prefs.remove('saved_licence');
      await prefs.remove('encrypted_private_key');
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const ActivationScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.teal.shade700, Colors.teal.shade900],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Card(
              elevation: 8,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 420),
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.teal.shade50,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.lock_person, size: 48, color: Colors.teal.shade700),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'ELAA DocPocket Med',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.teal),
                    ),
                    const SizedBox(height: 8),
                    if (_medecinNom.isNotEmpty || _medecinPrenom.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.blue.shade200),
                        ),
                        child: Text(
                          'Dr. $_medecinNom $_medecinPrenom',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.blue.shade900),
                        ),
                      ),
                    const SizedBox(height: 16),
                    const Text(
                      'Veuillez entrer votre code PIN pour accéder à vos dossiers médicaux.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 14, color: Colors.black54),
                    ),
                    const SizedBox(height: 24),
                    TextField(
                      controller: _pinController,
                      obscureText: true,
                      keyboardType: TextInputType.number,
                      autofocus: true,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 22, letterSpacing: 8, fontWeight: FontWeight.bold),
                      decoration: InputDecoration(
                        labelText: 'Code PIN à 4 chiffres',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        prefixIcon: const Icon(Icons.pin),
                      ),
                      onSubmitted: (_) => _unlockApp(),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.teal,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: _unlockApp,
                        icon: const Icon(Icons.lock_open),
                        label: const Text(
                          'Déverrouiller et Accéder',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.teal.shade800,
                          side: BorderSide(color: Colors.teal.shade300),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: () async {
                          _pinController.text = '1234';
                          await _applyPinAndGenerateKeys('1234');
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Code PIN configuré à 1234 avec succès.')),
                          );
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(builder: (_) => const DoctorDashboardScreen()),
                          );
                        },
                        icon: const Icon(Icons.flash_on, size: 18),
                        label: const Text(
                          'Définir 1234 comme PIN et Accéder',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Divider(color: Colors.grey.shade300),
                    TextButton.icon(
                      onPressed: _resetLicence,
                      icon: const Icon(Icons.swap_horiz, size: 18, color: Colors.black54),
                      label: const Text(
                        'Changer de licence / Réinitialiser',
                        style: TextStyle(color: Colors.black54, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
