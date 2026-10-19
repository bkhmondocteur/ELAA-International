import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:elaa_shared/elaa_shared.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'settings_screen.dart';

class ConsultationHistoryView extends StatefulWidget {
  final Consultation consultation;
  const ConsultationHistoryView({super.key, required this.consultation});

  @override
  State<ConsultationHistoryView> createState() => _ConsultationHistoryViewState();
}

class _ConsultationHistoryViewState extends State<ConsultationHistoryView> {
  bool _isLoading = true;
  Map<String, dynamic>? _patientData;
  Map<String, dynamic>? _rapportData;
  String? _ordonnance;
  Map<String, dynamic>? _privateData;
  Map<String, dynamic>? _financeData;
  String? _error;

  @override
  void initState() {
    super.initState();
    _decryptDossier();
  }

  Future<String?> _showPinDialog() async {
    final prefs = await SharedPreferences.getInstance();
    final savedPin = prefs.getString('saved_pin');
    String? pin;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        final c = TextEditingController();
        String? errorMsg;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.lock, color: Colors.teal),
                  SizedBox(width: 8),
                  Text('Sécurité ELAA - Code PIN'),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Entrez votre clé de sécurité (Code PIN) pour déchiffrer ce dossier archivé :'),
                  const SizedBox(height: 12),
                  TextField(
                    controller: c,
                    obscureText: true,
                    keyboardType: TextInputType.text,
                    decoration: InputDecoration(
                      labelText: 'Code PIN personnel',
                      errorText: errorMsg,
                      prefixIcon: const Icon(Icons.key),
                    ),
                    onSubmitted: (_) {
                      final entered = c.text.trim();
                      if (entered.isEmpty) {
                        setDialogState(() => errorMsg = 'Veuillez saisir votre code PIN');
                        return;
                      }
                      if (savedPin != null && savedPin.isNotEmpty && entered != savedPin) {
                        setDialogState(() => errorMsg = 'Code PIN incorrect. Veuillez réessayer.');
                        return;
                      }
                      pin = entered;
                      Navigator.pop(context);
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(context); // Cancel
                  },
                  child: const Text('Annuler'),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const SettingsScreen()),
                    );
                  },
                  child: const Text('Réglages'),
                ),
                ElevatedButton(
                  onPressed: () {
                    final entered = c.text.trim();
                    if (entered.isEmpty) {
                      setDialogState(() => errorMsg = 'Veuillez saisir votre code PIN');
                      return;
                    }
                    if (savedPin != null && savedPin.isNotEmpty && entered != savedPin) {
                      setDialogState(() => errorMsg = 'Code PIN incorrect. Veuillez réessayer.');
                      return;
                    }
                    pin = entered;
                    Navigator.pop(context);
                  },
                  child: const Text('Valider'),
                )
              ],
            );
          },
        );
      },
    );
    return pin;
  }

  Future<void> _decryptDossier() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final localBackupStr = prefs.getString('latest_backup_${widget.consultation.id}');
      if (localBackupStr != null) {
        try {
          final backup = jsonDecode(localBackupStr);
          final data = backup['data'] as Map<String, dynamic>?;
          if (data != null && data['patient'] != null) {
            setState(() {
              _patientData = data['patient'] != null ? Map<String, dynamic>.from(data['patient']) : null;
              _rapportData = data['rapport'] != null ? Map<String, dynamic>.from(data['rapport']) : null;
              _ordonnance = data['ordonnance']?.toString();
              _financeData = data['finance'] != null ? Map<String, dynamic>.from(data['finance']) : null;
              _isLoading = false;
            });
            return;
          }
        } catch (_) {}
      }

      final pin = await _showPinDialog();
      if (pin == null) return;
      
      setState(() { _isLoading = true; _error = null; });
      
      final encryptedPrivKey = prefs.getString('encrypted_private_key');
      if (encryptedPrivKey == null) throw Exception('Clé privée introuvable');

      final aesKeyFromPin = EncryptionEngine.deriveKeyFromPin(pin, widget.consultation.medecinId);
      final privKeyJson = EncryptionEngine.decryptDataAES(encryptedPrivKey, aesKeyFromPin);
      final rsaPrivKey = EncryptionEngine.parsePrivateKeyFromJson(privKeyJson);

      // Decrypt Shared AES Key
      final aesKeyBase64 = EncryptionEngine.decryptRSA(widget.consultation.encryptedKeyForMedecin, rsaPrivKey);
      final sharedAesKey = enc.Key.fromBase64(aesKeyBase64);

      // Decrypt Shared Patient Data
      if (widget.consultation.encryptedPatientData != null) {
        final jsonStr = EncryptionEngine.decryptDataAES(widget.consultation.encryptedPatientData!, sharedAesKey);
        _patientData = jsonDecode(jsonStr);
      }

      // Decrypt Shared Rapport
      if (widget.consultation.encryptedRapport != null) {
        final jsonStr = EncryptionEngine.decryptDataAES(widget.consultation.encryptedRapport!, sharedAesKey);
        _rapportData = jsonDecode(jsonStr);
      }

      // Decrypt Shared Ordonnance
      if (widget.consultation.encryptedOrdonnance != null) {
        _ordonnance = EncryptionEngine.decryptDataAES(widget.consultation.encryptedOrdonnance!, sharedAesKey);
      }

      // Decrypt Shared Financial Data
      if (widget.consultation.encryptedEtatFinancier != null) {
        final jsonStr = EncryptionEngine.decryptDataAES(widget.consultation.encryptedEtatFinancier!, sharedAesKey);
        _financeData = jsonDecode(jsonStr);
      }

      // Decrypt PRIVATE DOSSIER
      if (widget.consultation.encryptedDossierMedicalPrive != null) {
        final parts = widget.consultation.encryptedDossierMedicalPrive!.split('|');
        if (parts.length == 2) {
          final encPrivAesBase64 = parts[0];
          final encData = parts[1];
          // Decrypt the private AES key using Doctor's RSA Private Key
          final privateAesKeyBase64 = EncryptionEngine.decryptRSA(encPrivAesBase64, rsaPrivKey);
          final privateAesKey = enc.Key.fromBase64(privateAesKeyBase64);
          
          final jsonStr = EncryptionEngine.decryptDataAES(encData, privateAesKey);
          _privateData = jsonDecode(jsonStr);
        }
      }

      setState(() { _isLoading = false; });
    } catch (e) {
      String msg = e.toString();
      if (msg.contains('Unsupported block type') || msg.contains('Invalid argument') || msg.contains('RSA') || msg.contains('PKCS')) {
        msg = '⚠️ Clé de sécurité incompatible : Cette consultation a été créée avant la dernière réinitialisation de votre licence sur cet appareil. Veuillez créer une nouvelle demande depuis le Hub.';
      }
      setState(() { _isLoading = false; _error = msg; });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_error != null) return Scaffold(appBar: AppBar(), body: Center(child: Text('Erreur: $_error')));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dossier Médical & Historique Complet (Non Masqué)'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_patientData != null) _buildCard('Démographie & Identification Patient', [
              _buildRow('Nom & Prénom', '${_patientData!['nom'] ?? ''} ${_patientData!['prenom'] ?? ''}'),
              _buildRow('Date de naissance / Âge', '${_patientData!['dateNaissance'] ?? 'Non renseigné'} (${_patientData!['age'] ?? '-'} ans)'),
              _buildRow('Téléphone', _patientData!['telephone'] ?? _patientData!['tel'] ?? 'Non renseigné'),
              _buildRow('Ville / Origine', _patientData!['ville'] ?? _patientData!['origine'] ?? 'Non renseigné'),
              _buildRow('Hôtel & Chambre', '${_patientData!['hotel'] ?? 'N/A'} - Ch. ${_patientData!['chambre'] ?? 'N/A'}'),
              _buildRow('Garantie / N° Dossier ELAA', _patientData!['dossier'] ?? _patientData!['garantie'] ?? 'Non renseigné'),
            ]),
            
            const SizedBox(height: 16),
            
            if (_privateData != null) Card(
              color: Colors.red.shade50,
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.lock_open, color: Colors.red),
                        SizedBox(width: 8),
                        Text('Notes Strictement Privées Médecin', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 18)),
                      ],
                    ),
                    const Divider(color: Colors.red),
                    _buildRow('Antécédents / ATCD', _privateData!['atcd'] ?? 'Aucun'),
                    _buildRow('Allergies', _privateData!['allergies'] ?? 'Aucune'),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 16),
            
            if (_rapportData != null) _buildCard('Examen Clinique & Rapport Médical', [
              _buildRow('Motif de consultation', _rapportData!['motif'] ?? 'Non renseigné'),
              _buildRow('Histoire de la maladie', _rapportData!['histoire'] ?? 'Non renseigné'),
              _buildRow('Constantes vitales', 'Poids: ${_rapportData!['poids'] ?? '-'} | TA: ${_rapportData!['ta'] ?? '-'} | Pouls: ${_rapportData!['pouls'] ?? '-'} | Temp: ${_rapportData!['temp'] ?? '-'} | SpO2: ${_rapportData!['spo2'] ?? '-'}'),
              _buildRow('Examen Général', _rapportData!['examGeneral'] ?? 'Non renseigné'),
              _buildRow('Examen ORL', _rapportData!['examOrl'] ?? 'Non renseigné'),
              _buildRow('Examen Cardiovasculaire', _rapportData!['examCardio'] ?? 'Non renseigné'),
              _buildRow('Examen Pulmonaire / Respiratoire', _rapportData!['examResp'] ?? 'Non renseigné'),
              _buildRow('Examen Abdominal', _rapportData!['examAbdo'] ?? 'Non renseigné'),
              _buildRow('Examen Neurologique', _rapportData!['examNeuro'] ?? 'Non renseigné'),
              _buildRow('Diagnostic', _rapportData!['diagnostic'] ?? 'Non renseigné'),
              _buildRow('État préexistant', _rapportData!['preexistant'] == true ? 'Oui' : 'Non'),
              _buildRow('Recommandations', _rapportData!['recommandations'] ?? 'Aucune'),
              if (_rapportData!['soins'] != null) _buildRow('Soins pratiqués', _rapportData!['soins']),
              if (_rapportData!['observations'] != null) _buildRow('Observations cliniques', _rapportData!['observations']),
            ]),

            const SizedBox(height: 16),

            if (_ordonnance != null && _ordonnance!.isNotEmpty) _buildCard('Ordonnance Prescrite', [
              Text(_ordonnance!, style: const TextStyle(fontSize: 15, height: 1.4)),
            ]),

            const SizedBox(height: 16),

            if (_financeData != null) _buildCard('Décompte Financier & Honoraires', [
              _buildRow('Honoraires', '${_financeData!['honoraires'] ?? '0.000'} DT'),
              _buildRow('Soins / Sutures / Injections', 'Injections: ${_financeData!['injections'] == true ? "Oui (${_financeData!['qtyInjections'] ?? 0})" : "Non"} | Sutures: ${_financeData!['sutures'] == true ? "Oui (${_financeData!['qtySutures'] ?? 0})" : "Non"} | Soins: ${_financeData!['soins'] == true ? "Oui" : "Non"}'),
              _buildRow('Sous-total HT', '${_financeData!['totalHT'] ?? '0.000'} DT'),
              _buildRow('TVA (${_financeData!['tva'] ?? '7'} %)', '${_financeData!['tvaAmount'] ?? '0.000'} DT'),
              _buildRow('Total TTC', '${_financeData!['totalTTC'] ?? '0.000'} DT', isBold: true),
              _buildRow('Franchise / Payé patient', '${_financeData!['franchise'] ?? '0.000'} DT'),
              _buildRow('Net à payer (Prise en charge)', '${_financeData!['netAPayer'] ?? '0.000'} DT', isBold: true),
              _buildRow('Mode de règlement', _financeData!['couverture'] ?? 'Prise en charge'),
            ]),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
  
  Widget _buildCard(String title, List<Widget> children) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold, color: Colors.blue.shade900)),
            const Divider(),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildRow(String label, String value, {bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 180,
            child: Text(
              label,
              style: TextStyle(
                fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
                color: Colors.grey.shade700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
                color: isBold ? Colors.blue.shade900 : Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
