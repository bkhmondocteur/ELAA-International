import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:elaa_shared/crypto/encryption_engine.dart';
import 'package:elaa_shared/services/local_backup_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String? _logoBase64;
  String? _ordonnanceBase64;
  String? _tamponBase64;

  String? _medecinId;
  String _medecinNom = '';
  String _medecinPrenom = '';
  String? _savedPin;
  String? _licenceKey;
  bool _hasPrivateKey = false;
  String _backupFolder = '';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    String? medId = prefs.getString('medecin_id');
    String nom = prefs.getString('medecin_nom') ?? '';
    String prenom = prefs.getString('medecin_prenom') ?? '';
    String? licence = prefs.getString('saved_licence');
    final pin = prefs.getString('saved_pin');
    final hasPrivKey = prefs.getString('encrypted_private_key') != null;

    if (medId == null) {
      try {
        final snap = await FirebaseFirestore.instance.collection('medecins').get();
        if (snap.docs.isNotEmpty) {
          final hamed = snap.docs.firstWhere(
            (d) => (d.data()['nom']?.toString().toUpperCase().contains('BEN KHALIFA') == true),
            orElse: () => snap.docs.firstWhere((d) => d.data()['statut'] == 'Actif', orElse: () => snap.docs.first),
          );
          medId = hamed.id;
          nom = hamed.data()['nom'] ?? '';
          prenom = hamed.data()['prenom'] ?? '';
          licence = hamed.data()['licenceKey'] ?? licence;
          await prefs.setString('medecin_id', medId);
          await prefs.setString('medecin_nom', nom);
          await prefs.setString('medecin_prenom', prenom);
        }
      } catch (_) {}
    } else if (licence == null || nom.isEmpty) {
      try {
        final doc = await FirebaseFirestore.instance.collection('medecins').doc(medId).get();
        if (doc.exists && doc.data() != null) {
          nom = doc.data()!['nom'] ?? nom;
          prenom = doc.data()!['prenom'] ?? prenom;
          licence = doc.data()!['licenceKey'] ?? licence;
          if (licence != null) await prefs.setString('saved_licence', licence);
        }
      } catch (_) {}
    }

    final folder = await LocalBackupService.getBackupFolder();

    if (mounted) {
      setState(() {
        _medecinId = medId;
        _medecinNom = nom;
        _medecinPrenom = prenom;
        _savedPin = pin;
        _licenceKey = licence;
        _hasPrivateKey = hasPrivKey;
        _backupFolder = folder;
        _logoBase64 = prefs.getString('settings_logo');
        _ordonnanceBase64 = prefs.getString('settings_ordonnance');
        _tamponBase64 = prefs.getString('settings_tampon');
        _isLoading = false;
      });
    }
  }

  Future<void> _pickImage(String key) async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      final bytes = await pickedFile.readAsBytes();
      final base64String = base64Encode(bytes);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, base64String);
      setState(() {
        if (key == 'settings_logo') _logoBase64 = base64String;
        if (key == 'settings_ordonnance') _ordonnanceBase64 = base64String;
        if (key == 'settings_tampon') _tamponBase64 = base64String;
      });
    }
  }

  Future<void> _showChangeSecurityKeyDialog() async {
    final oldPinController = TextEditingController();
    final newPinController = TextEditingController();
    final confirmPinController = TextEditingController();
    bool obscureOld = true;
    bool obscureNew = true;
    bool obscureConfirm = true;
    String? errorText;
    bool isProcessing = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Row(
              children: [
                Icon(Icons.security, color: Colors.teal),
                SizedBox(width: 8),
                Text('Clé de Sécurité Médecin', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
            content: SizedBox(
              width: 440,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Confirmez votre identité avec votre ancienne clé de sécurité (ou votre clé de licence en cas d\'oubli), puis définissez votre nouvelle clé.',
                      style: TextStyle(fontSize: 13, color: Colors.black87),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: oldPinController,
                      obscureText: obscureOld,
                      decoration: InputDecoration(
                        labelText: 'Ancienne clé de sécurité (ou Clé de licence)',
                        helperText: 'Code PIN actuel ou clé de licence ELAA',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(obscureOld ? Icons.visibility : Icons.visibility_off),
                          onPressed: () => setDialogState(() => obscureOld = !obscureOld),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: newPinController,
                      obscureText: obscureNew,
                      keyboardType: TextInputType.text,
                      decoration: InputDecoration(
                        labelText: 'Nouvelle clé de sécurité (Code PIN)',
                        helperText: '4 caractères ou chiffres minimum',
                        prefixIcon: const Icon(Icons.key),
                        suffixIcon: IconButton(
                          icon: Icon(obscureNew ? Icons.visibility : Icons.visibility_off),
                          onPressed: () => setDialogState(() => obscureNew = !obscureNew),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: confirmPinController,
                      obscureText: obscureConfirm,
                      keyboardType: TextInputType.text,
                      decoration: InputDecoration(
                        labelText: 'Confirmer la nouvelle clé',
                        prefixIcon: const Icon(Icons.check_circle_outline),
                        suffixIcon: IconButton(
                          icon: Icon(obscureConfirm ? Icons.visibility : Icons.visibility_off),
                          onPressed: () => setDialogState(() => obscureConfirm = !obscureConfirm),
                        ),
                      ),
                    ),
                    if (errorText != null) ...[
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.red.shade300),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline, color: Colors.red, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                errorText!,
                                style: const TextStyle(color: Colors.red, fontSize: 13, fontWeight: FontWeight.w500),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (isProcessing) ...[
                      const SizedBox(height: 16),
                      const Center(
                        child: Column(
                          children: [
                            CircularProgressIndicator(),
                            SizedBox(height: 10),
                            Text('Génération de la paire de clés RSA & synchronisation Cloud...', style: TextStyle(fontSize: 12)),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: isProcessing ? null : () => Navigator.pop(ctx),
                child: const Text('Annuler'),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
                icon: const Icon(Icons.sync_lock, size: 20),
                label: const Text('Enregistrer et Transmettre'),
                onPressed: isProcessing
                    ? null
                    : () async {
                        final oldInput = oldPinController.text.trim();
                        final newInput = newPinController.text.trim();
                        final confirmInput = confirmPinController.text.trim();

                        setDialogState(() => errorText = null);

                        bool oldValid = false;
                        if (_savedPin != null && _savedPin!.isNotEmpty && oldInput == _savedPin) {
                          oldValid = true;
                        } else if (_licenceKey != null && _licenceKey!.isNotEmpty && oldInput.toLowerCase() == _licenceKey!.toLowerCase()) {
                          oldValid = true;
                        } else if (_savedPin == null || _savedPin!.isEmpty) {
                          if (_licenceKey != null && oldInput.toLowerCase() == _licenceKey!.toLowerCase()) {
                            oldValid = true;
                          } else if (oldInput.isNotEmpty) {
                            oldValid = true;
                          }
                        }

                        if (!oldValid) {
                          setDialogState(() {
                            errorText = 'Ancienne clé incorrecte. Veuillez entrer votre clé de sécurité actuelle ou votre clé de licence.';
                          });
                          return;
                        }

                        if (newInput.length < 4) {
                          setDialogState(() {
                            errorText = 'La nouvelle clé doit comporter au moins 4 caractères.';
                          });
                          return;
                        }

                        if (newInput != confirmInput) {
                          setDialogState(() {
                            errorText = 'La confirmation ne correspond pas à la nouvelle clé.';
                          });
                          return;
                        }

                        if (_medecinId == null || _medecinId!.isEmpty) {
                          setDialogState(() {
                            errorText = 'Identifiant médecin introuvable. Veuillez recharger l\'application.';
                          });
                          return;
                        }

                        setDialogState(() => isProcessing = true);

                        try {
                          // 1. Génération nouvelle paire RSA
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

                          // 2. Dérivation clé AES depuis le nouveau PIN
                          final aesKey = EncryptionEngine.deriveKeyFromPin(newInput, _medecinId!);
                          final encryptedPrivKey = EncryptionEngine.encryptDataAES(privJson, aesKey);

                          // 3. Mise à jour Firestore pour que le Hub l'utilise automatiquement
                          await FirebaseFirestore.instance.collection('medecins').doc(_medecinId).update({
                            'publicKeyBase64': pubBase64,
                            'dateMiseAJourCle': FieldValue.serverTimestamp(),
                          });

                          // 4. Sauvegarde locale SharedPreferences
                          final prefs = await SharedPreferences.getInstance();
                          await prefs.setString('encrypted_private_key', encryptedPrivKey);
                          await prefs.setString('saved_pin', newInput);

                          if (!mounted) return;
                          Navigator.pop(ctx);

                          setState(() {
                            _savedPin = newInput;
                            _hasPrivateKey = true;
                          });

                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Row(
                                children: [
                                  Icon(Icons.check_circle, color: Colors.white),
                                  SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      '✓ Clé de sécurité modifiée avec succès ! La nouvelle clé publique a été transmise à Firestore et à l\'espace Hub.',
                                    ),
                                  ),
                                ],
                              ),
                              backgroundColor: Colors.teal,
                              duration: Duration(seconds: 6),
                            ),
                          );
                        } catch (e) {
                          setDialogState(() {
                            isProcessing = false;
                            errorText = 'Erreur lors de la mise à jour: $e';
                          });
                        }
                      },
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSecurityKeyCard() {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: Colors.teal.shade100,
                  child: const Icon(Icons.enhanced_encryption, color: Colors.teal),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Clé de Sécurité & Chiffrement de Bout en Bout',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _hasPrivateKey
                            ? 'Protégé par clé RSA-1024 + AES-256 (Actif)'
                            : 'Clé non initialisée sur cet appareil',
                        style: TextStyle(
                          fontSize: 13,
                          color: _hasPrivateKey ? Colors.green.shade800 : Colors.orange.shade800,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            Text(
              'Médecin : Dr. $_medecinPrenom $_medecinNom',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            ),
            if (_licenceKey != null && _licenceKey!.isNotEmpty)
              Text('Licence ELAA : $_licenceKey', style: TextStyle(color: Colors.grey.shade700, fontSize: 13)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, color: Colors.blue, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'La clé de sécurité protège les fiches médicales et l\'identité des patients. En la modifiant, la nouvelle clé publique est transmise au Hub pour que tous les prochains envois soient automatiquement chiffrés avec cette nouvelle clé. Vos anciennes archives restent consultables localement.',
                      style: TextStyle(fontSize: 12, color: Colors.black87),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onPressed: _showChangeSecurityKeyDialog,
                icon: const Icon(Icons.lock_reset),
                label: Text(
                  _savedPin != null ? 'Modifier la clé de sécurité' : 'Définir la clé de sécurité',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBackupFolderCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: Colors.blue.shade100,
                  child: const Icon(Icons.folder, color: Colors.blue),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Emplacement de Sauvegarde Locale',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              _backupFolder.isNotEmpty ? _backupFolder : 'Non configuré',
              style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: () async {
                await LocalBackupService.showFolderSelectionDialog(context, forced: true);
                final updated = await LocalBackupService.getBackupFolder();
                setState(() => _backupFolder = updated);
              },
              icon: const Icon(Icons.edit_location_alt, size: 18),
              label: const Text('Modifier l\'emplacement de sauvegarde'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImageSetting({
    required String title,
    required String? base64Data,
    required String key,
  }) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 12),
            base64Data != null
                ? Image.memory(
                    base64Decode(base64Data),
                    height: 120,
                    fit: BoxFit.contain,
                  )
                : const Icon(Icons.image, size: 80, color: Colors.grey),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: () => _pickImage(key),
              icon: const Icon(Icons.upload),
              label: const Text('Uploader'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Réglages Médecin'),
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16.0),
              children: [
                _buildSecurityKeyCard(),
                const SizedBox(height: 16),
                _buildBackupFolderCard(),
                const SizedBox(height: 16),
                const Text('Personnalisation des Documents', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 8),
                _buildImageSetting(
                  title: 'Logo du Cabinet',
                  base64Data: _logoBase64,
                  key: 'settings_logo',
                ),
                _buildImageSetting(
                  title: 'Modèle de l\'Ordonnance (Entête)',
                  base64Data: _ordonnanceBase64,
                  key: 'settings_ordonnance',
                ),
                _buildImageSetting(
                  title: 'Tampon et Signature',
                  base64Data: _tamponBase64,
                  key: 'settings_tampon',
                ),
              ],
            ),
    );
  }
}
