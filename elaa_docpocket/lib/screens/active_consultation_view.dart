import 'dart:convert';
import 'dart:typed_data';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:elaa_shared/elaa_shared.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../hub_security_manager.dart';
import '../doctor_name_badge.dart';
import '../widgets/live_doctor_tracking_dialog.dart';
import '../utils/mail_launcher.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:io';

class ActiveConsultationView extends StatefulWidget {
  final Consultation consultation;
  final bool isHistory;
  const ActiveConsultationView({super.key, required this.consultation, this.isHistory = false});

  @override
  State<ActiveConsultationView> createState() => _ActiveConsultationViewState();
}

class _ActiveConsultationViewState extends State<ActiveConsultationView> {
  bool _isLoading = true;
  String? _error;
  
  Map<String, dynamic>? _patientData;
  Map<String, dynamic>? _rapportData;
  Map<String, dynamic>? _financeData;
  String? _ordonnance;
  String? _passportUrl;
  String? _garantieUrl;

  @override
  void initState() {
    super.initState();
    _decryptData();
  }
  
  @override
  void didUpdateWidget(ActiveConsultationView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.consultation.statut != widget.consultation.statut || 
        oldWidget.consultation.encryptedRapport != widget.consultation.encryptedRapport) {
      _decryptData();
    }
  }

  Future<void> _decryptData() async {
    try {
      setState(() { _isLoading = true; _error = null; });
      
      final hubPrivKey = await HubSecurityManager.getPrivateKey();

      final aesKeyBase64 = EncryptionEngine.decryptRSA(widget.consultation.encryptedKeyForHub, hubPrivKey);
      final aesKey = enc.Key.fromBase64(aesKeyBase64);

      if (widget.consultation.encryptedPatientData != null) {
        final jsonStr = EncryptionEngine.decryptDataAES(widget.consultation.encryptedPatientData!, aesKey);
        _patientData = jsonDecode(jsonStr);
      }

      if (widget.consultation.encryptedRapport != null) {
        final jsonStr = EncryptionEngine.decryptDataAES(widget.consultation.encryptedRapport!, aesKey);
        _rapportData = jsonDecode(jsonStr);
      }

      if (widget.consultation.encryptedOrdonnance != null) {
        _ordonnance = EncryptionEngine.decryptDataAES(widget.consultation.encryptedOrdonnance!, aesKey);
      }

      if (widget.consultation.encryptedEtatFinancier != null) {
        final jsonStr = EncryptionEngine.decryptDataAES(widget.consultation.encryptedEtatFinancier!, aesKey);
        _financeData = jsonDecode(jsonStr);
      }

      if (widget.consultation.encryptedPassportUrl != null) {
        _passportUrl = EncryptionEngine.decryptDataAES(widget.consultation.encryptedPassportUrl!, aesKey);
      }

      if (widget.consultation.encryptedGarantieUrl != null) {
        _garantieUrl = EncryptionEngine.decryptDataAES(widget.consultation.encryptedGarantieUrl!, aesKey);
      } else if (_patientData != null && _patientData!['garantieUrl'] != null) {
        _garantieUrl = _patientData!['garantieUrl'];
      }

      if (_patientData != null || _rapportData != null) {
        LocalBackupService.saveAutoBackup(
          consultationId: widget.consultation.id,
          medecinId: widget.consultation.medecinId,
          data: {
            'patient': _patientData,
            'rapport': _rapportData,
            'ordonnance': _ordonnance,
            'finance': _financeData,
            'statut': widget.consultation.statut,
          },
        );
      }

      await _syncBridgeFiles();

      setState(() { _isLoading = false; });
    } catch (e) {
      setState(() { _isLoading = false; _error = e.toString(); });
    }
  }

  void _cloturer() {
    FirebaseFirestore.instance
        .collection('consultations')
        .doc(widget.consultation.id)
        .update({'statut': 'Clôturée'});
  }

  Future<void> _sauvegarderLocalement() async {
    await LocalBackupService.saveAutoBackup(
      consultationId: widget.consultation.id,
      medecinId: widget.consultation.medecinId,
      data: {
        'patient': _patientData,
        'rapport': _rapportData,
        'ordonnance': _ordonnance,
        'finance': _financeData,
        'statut': widget.consultation.statut,
      },
      isManual: true,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Dossier et pièces jointes sauvegardés localement (Archivage mensuel YYYY-MM / Rotation 10).'),
        backgroundColor: Colors.green,
      ),
    );
  }

  void _openLiveGpsTracking() {
    final nom = _patientData?['nom'] ?? '';
    final prenom = _patientData?['prenom'] ?? '';
    showDialog(
      context: context,
      builder: (_) => LiveDoctorTrackingDialog(
        consultationId: widget.consultation.id,
        doctorName: 'Dr. ID ${widget.consultation.medecinId.substring(0, math.min(6, widget.consultation.medecinId.length))}',
        patientName: '$prenom $nom',
      ),
    );
  }

  void _sendMailHub() {
    final nom = _patientData?['nom'] ?? '';
    final prenom = _patientData?['prenom'] ?? '';
    final dossier = _patientData?['dossier'] ?? _patientData?['garantie'] ?? widget.consultation.id;

    final rapportMedicalTxt = '=========================================\n'
        '  RAPPORT MÉDICAL (Strictement Médical)\n'
        '     ELAA DocPocket Pro Hub\n'
        '=========================================\n'
        'Dossier ELAA: $dossier\n'
        'Patient: $nom $prenom\n'
        'Date: ${DateTime.now().toString().substring(0, 16)}\n\n'
        '--- EXAMEN CLINIQUE ---\n'
        '• Motif: ${_rapportData?['motif'] ?? 'N/A'}\n'
        '• Histoire: ${_rapportData?['histoire'] ?? 'N/A'}\n'
        '• Constantes: Poids=${_rapportData?['poids']} | Taille=${_rapportData?['taille']} | TA=${_rapportData?['ta']} | Pouls=${_rapportData?['pouls']} | Temp=${_rapportData?['temp']} | SpO2=${_rapportData?['spo2']}\n'
        '• Examen Général: ${_rapportData?['examGeneral'] ?? 'N/A'}\n'
        '• Examen ORL: ${_rapportData?['examOrl'] ?? 'N/A'}\n'
        '• Examen Cardiovasculaire: ${_rapportData?['examCardio'] ?? 'N/A'}\n'
        '• Examen Pulmonaire: ${_rapportData?['examResp'] ?? 'N/A'}\n'
        '• Examen Abdominal: ${_rapportData?['examAbdo'] ?? 'N/A'}\n'
        '• Examen Neurologique: ${_rapportData?['examNeuro'] ?? 'N/A'}\n'
        '• Divers / Autres: ${_rapportData?['examOther'] ?? 'N/A'}\n'
        '• Diagnostic: ${_rapportData?['diagnostic'] ?? 'N/A'}\n'
        '• Observations: ${_rapportData?['observations'] ?? _rapportData?['recommandations'] ?? ''}\n\n'
        '--- ORDONNANCE ---\n'
        '${_ordonnance ?? 'N/A'}\n\n'
        '(Note : Ce rapport médical est distinct de la facturation et ne comporte aucune donnée financière.)';

    final rapportFinancierTxt = '=========================================\n'
        '  RAPPORT FINANCIER & NOTE D\'HONORAIRES\n'
        '     ELAA International - Facturation\n'
        '=========================================\n'
        'Dossier ELAA: $dossier\n'
        'Patient: $nom $prenom\n'
        'Date: ${DateTime.now().toString().substring(0, 16)}\n'
        'Couverture: ${_financeData?['couverture'] ?? 'N/A'}\n\n'
        '--- DÉTAIL DES ACTES ET HONORAIRES (HT) ---\n'
        '• Honoraires HT: ${_financeData?['honoraires'] ?? '0.000'} DT\n'
        '• TVA applicable: ${_financeData?['tva'] ?? '7'} %\n'
        '• Injections: ${_financeData?['injections'] == true ? "Oui (x${_financeData?['qtyInjections'] ?? 1})" : "Non"}\n'
        '• Points de suture: ${_financeData?['sutures'] == true ? "Oui (x${_financeData?['qtySutures'] ?? 1})" : "Non"}\n'
        '• Soins / Pansements: ${_financeData?['soins'] == true ? "Oui" : "Non"}\n\n'
        '--- SYNTHÈSE ET PRISES EN CHARGE (TTC) ---\n'
        '• Total HT: ${_financeData?['totalHT'] ?? '0.000'} DT\n'
        '• Montant TVA: ${_financeData?['tvaAmount'] ?? '0.000'} DT\n'
        '• Total TTC: ${_financeData?['totalTTC'] ?? '0.000'} DT\n'
        '• Net à payer par Assurance: ${_financeData?['netAPayer'] ?? '0.000'} DT\n'
        '• Pièce d\'identité: ${_passportUrl ?? 'N/A'}\n'
        '• Garantie/Prise en charge: ${_garantieUrl ?? 'N/A'}\n\n'
        '(Note : Ce rapport financier est distinct de l\'examen clinique.)';

    showDialog(
      context: context,
      builder: (ctx) => DefaultTabController(
        length: 2,
        child: AlertDialog(
          title: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(Icons.mark_email_read, color: Colors.blue),
                  SizedBox(width: 8),
                  Text('Expédition Email : Rapports - ELAA HUB'),
                ],
              ),
              SizedBox(height: 12),
              TabBar(
                labelColor: Colors.blue,
                unselectedLabelColor: Colors.grey,
                indicatorColor: Colors.blue,
                tabs: [
                  Tab(icon: Icon(Icons.medical_information, size: 18), text: '1. Rapport Médical (Sans prix)'),
                  Tab(icon: Icon(Icons.request_quote, size: 18), text: '2. Rapport Financier (Facturation)'),
                ],
              ),
            ],
          ),
          content: SizedBox(
            width: 550,
            height: 420,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TabBarView(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)),
                        child: SingleChildScrollView(child: Text(rapportMedicalTxt, style: const TextStyle(fontFamily: 'monospace', fontSize: 12))),
                      ),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)),
                        child: SingleChildScrollView(child: Text(rapportFinancierTxt, style: const TextStyle(fontFamily: 'monospace', fontSize: 12))),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(4)),
                  child: const Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.blue, size: 18),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Expédition de 2 documents PDF : 1) Rapport Médical PDF (clinique unique), 2) Rapport Financier PDF (honoraires) + Ordonnance & Pièces justificatives.',
                          style: TextStyle(fontSize: 11, color: Colors.blue),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: rapportMedicalTxt));
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Rapport Médical copié dans le presse-papiers.')));
              },
              icon: const Icon(Icons.copy, size: 16),
              label: const Text('Copier Médical'),
            ),
            TextButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: rapportFinancierTxt));
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Rapport Financier copié dans le presse-papiers.')));
              },
              icon: const Icon(Icons.copy, size: 16),
              label: const Text('Copier Financier'),
            ),
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Fermer')),
            ElevatedButton.icon(
              onPressed: () async {
                Navigator.pop(ctx);
                await _sauvegarderLocalement();
                final nom = _patientData?['nom'] ?? '';
                final prenom = _patientData?['prenom'] ?? '';
                final motif = _patientData?['motif'] ?? 'Consultation médicale';
                final safeNom = nom.trim().replaceAll(' ', '_');
                final safePrenom = prenom.trim().replaceAll(' ', '_');
                final patientTag = (safeNom.isNotEmpty || safePrenom.isNotEmpty) ? '${safeNom}_$safePrenom' : 'Patient';

                final subject = '[ELAA International] Dossier Médical et Financier - $nom $prenom';
                final body = '''Bonjour,

Veuillez trouver ci-joint les documents médicaux et administratifs pour :
- Patient(e) : $nom $prenom
- Motif : $motif
- Statut : ${widget.consultation.statut}

Documents joints à cet email :
1. Rapport Médical complet (clinique & observations sans données financières)
2. Rapport Financier (honoraires & facturation)
3. Ordonnance Médicale & Pièces justificatives

Cordialement,
ELAA International DocPocket Pro Hub''';

                try {
                  List<EmailAttachment> attachments = [];

                  // 1. Rapport Médical (PDF)
                  final medBytes = await _generatePdfBytes('Rapport de Consultation Médicale', rapportMedicalTxt);
                  attachments.add(EmailAttachment(
                    filename: 'Rapport_Medical_$patientTag.pdf',
                    bytes: medBytes,
                    mimeType: 'application/pdf',
                  ));

                  // 2. Rapport Financier (PDF)
                  final finBytes = await _generatePdfBytes('Rapport Financier & Facturation', rapportFinancierTxt);
                  attachments.add(EmailAttachment(
                    filename: 'Rapport_Financier_$patientTag.pdf',
                    bytes: finBytes,
                    mimeType: 'application/pdf',
                  ));

                  // 3. Ordonnance (PDF) si disponible
                  if (_ordonnance != null && _ordonnance!.trim().isNotEmpty) {
                    final ordBytes = await _generatePdfBytes('Ordonnance Médicale', _ordonnance!);
                    attachments.add(EmailAttachment(
                      filename: 'Ordonnance_$patientTag.pdf',
                      bytes: ordBytes,
                      mimeType: 'application/pdf',
                    ));
                  }

                  // 4. Document d'identité (Passeport / CNI)
                  if (_passportUrl != null && _passportUrl!.isNotEmpty) {
                    try {
                      Uint8List? bytes;
                      String ext = 'jpg';
                      if (_passportUrl!.startsWith('data:')) {
                        final commaIdx = _passportUrl!.indexOf(',');
                        if (commaIdx != -1) {
                          bytes = base64Decode(_passportUrl!.substring(commaIdx + 1));
                        }
                      } else if (!kIsWeb && File(_passportUrl!).existsSync()) {
                        bytes = await File(_passportUrl!).readAsBytes();
                        if (_passportUrl!.contains('.')) ext = _passportUrl!.split('.').last;
                      }
                      if (bytes != null) {
                        attachments.add(EmailAttachment(
                          filename: 'Piece_Identite_$patientTag.$ext',
                          bytes: bytes,
                          mimeType: ext.toLowerCase() == 'pdf' ? 'application/pdf' : 'image/jpeg',
                        ));
                      }
                    } catch (e) {
                      debugPrint('Erreur lecture pièce identité Hub: $e');
                    }
                  }

                  // 5. Garantie / Prise en charge
                  if (_garantieUrl != null && _garantieUrl!.isNotEmpty) {
                    try {
                      Uint8List? bytes;
                      String ext = 'pdf';
                      if (_garantieUrl!.startsWith('data:')) {
                        final commaIdx = _garantieUrl!.indexOf(',');
                        if (commaIdx != -1) {
                          bytes = base64Decode(_garantieUrl!.substring(commaIdx + 1));
                        }
                      } else if (!kIsWeb && File(_garantieUrl!).existsSync()) {
                        bytes = await File(_garantieUrl!).readAsBytes();
                        if (_garantieUrl!.contains('.')) ext = _garantieUrl!.split('.').last;
                      }
                      if (bytes != null) {
                        attachments.add(EmailAttachment(
                          filename: 'Garantie_Paiement_$patientTag.$ext',
                          bytes: bytes,
                          mimeType: ext.toLowerCase() == 'pdf' ? 'application/pdf' : 'image/jpeg',
                        ));
                      }
                    } catch (e) {
                      debugPrint('Erreur lecture garantie Hub: $e');
                    }
                  }

                  final success = await launchMailWithAttachments(
                    subject: subject,
                    body: body,
                    attachments: attachments,
                  );

                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          success
                              ? 'Application Mail ouverte avec ${attachments.length} pièces jointes attachées (Rapports, Ordonnance & Documents).'
                              : 'Préparation terminée (${attachments.length} fichiers). Client Mail ouvert.',
                        ),
                        backgroundColor: Colors.blue.shade700,
                      ),
                    );
                  }
                } catch (e) {
                  debugPrint('Erreur envoi mail hub: $e');
                  await launchMail(subject, body);
                }
              },
              icon: const Icon(Icons.mark_email_read),
              label: const Text('Ouvrir l\'application Mail'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _relancerVisiteControle() async {
    if (_patientData == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.autorenew, color: Colors.green),
            SizedBox(width: 8),
            Text('Nouvelle Visite de Contrôle'),
          ],
        ),
        content: Text(
          'Voulez-vous lancer une nouvelle demande de visite de contrôle pour le patient ${_patientData!['nom']} ${_patientData!['prenom']} avec le médecin (ID: ${widget.consultation.medecinId}) ?\n\n'
          'Le dossier ELAA, l\'hôtel, et les pièces jointes du patient seront automatiquement joints à cette nouvelle consultation.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.check),
            label: const Text('Créer Visite de Contrôle'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      setState(() => _isLoading = true);
      try {
        final docRef = FirebaseFirestore.instance.collection('consultations').doc();
        final aesKey = EncryptionEngine.generateConsultationKey();
        final newPatientData = {
          ..._patientData!,
          if (_garantieUrl != null) 'garantieUrl': _garantieUrl,
          if (_passportUrl != null) 'passportUrl': _passportUrl,
          'motif': 'Visite de contrôle (suite du dossier ELAA ${_patientData!['dossier'] ?? _patientData!['garantie'] ?? ''})',
        };
        final patientJson = jsonEncode(newPatientData);
        final encryptedPatientData = EncryptionEngine.encryptDataAES(patientJson, aesKey);

        String? newEncryptedPassportUrl;
        if (_passportUrl != null && _passportUrl!.isNotEmpty) {
          newEncryptedPassportUrl = EncryptionEngine.encryptDataAES(_passportUrl!, aesKey);
        }
        String? newEncryptedGarantieUrl;
        if (_garantieUrl != null && _garantieUrl!.isNotEmpty) {
          newEncryptedGarantieUrl = EncryptionEngine.encryptDataAES(_garantieUrl!, aesKey);
        }

        // Encrypt for Doctor
        final medDoc = await FirebaseFirestore.instance.collection('medecins').doc(widget.consultation.medecinId).get();
        final pubKeyStr = medDoc.data()?['publicKeyBase64'] as String?;
        String encryptedKeyForMedecin = '';
        if (pubKeyStr != null && pubKeyStr.isNotEmpty) {
          final medPubKey = EncryptionEngine.parsePublicKeyFromBase64(pubKeyStr);
          encryptedKeyForMedecin = EncryptionEngine.encryptRSA(aesKey.base64, medPubKey);
        }

        // Encrypt for Hub
        final hubPubKey = await HubSecurityManager.getPublicKey();
        final encryptedKeyForHub = EncryptionEngine.encryptRSA(aesKey.base64, hubPubKey);

        final newCons = Consultation(
          id: docRef.id,
          medecinId: widget.consultation.medecinId,
          patientNom: _patientData!['nom'],
          patientPrenom: _patientData!['prenom'],
          statut: 'En attente',
          encryptedKeyForHub: encryptedKeyForHub,
          encryptedKeyForMedecin: encryptedKeyForMedecin,
          encryptedPatientData: encryptedPatientData,
          encryptedPassportUrl: newEncryptedPassportUrl,
          encryptedGarantieUrl: newEncryptedGarantieUrl,
        );

        await docRef.set({
          ...newCons.toMap(),
          'dateCreation': DateTime.now().toIso8601String(),
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Nouvelle visite de contrôle créée et transmise au médecin en charge !'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erreur création visite de contrôle: $e'), backgroundColor: Colors.red),
          );
        }
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  void _showDocumentDialog(BuildContext context, String title, String url) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 600,
          height: 500,
          child: Column(
            children: [
              Expanded(
                child: url.startsWith('http')
                    ? Image.network(
                        url,
                        fit: BoxFit.contain,
                        errorBuilder: (ctx, err, stack) => _buildErrorFallback(url),
                      )
                    : Image.file(
                        File(url),
                        fit: BoxFit.contain,
                        errorBuilder: (ctx, err, stack) => _buildErrorFallback(url),
                      ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Fermer')),
        ],
      ),
    );
  }

  Widget _buildErrorFallback(String url) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.picture_as_pdf, size: 64, color: Colors.red),
          const SizedBox(height: 16),
          const Text('Document PDF ou Fichier joint', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          SelectableText(url, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: Colors.blue)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(child: Text('Erreur de déchiffrement: $_error', style: const TextStyle(color: Colors.red)));
    }

    final isEnAttente = widget.consultation.encryptedRapport == null;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  widget.isHistory ? 'Dossier Partagé - Historique' : 'Dossier Partagé - Consultation',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
              ),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
                    onPressed: _sendMailHub,
                    icon: const Icon(Icons.mail),
                    label: const Text('Mail (PDF & Pièces)'),
                  ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white),
                    onPressed: _sauvegarderLocalement,
                    icon: const Icon(Icons.save_alt),
                    label: const Text('Sauvegarder'),
                  ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white),
                    onPressed: _openLiveGpsTracking,
                    icon: const Icon(Icons.satellite_alt),
                    label: const Text('Suivi GPS en direct'),
                  ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                    onPressed: _relancerVisiteControle,
                    icon: const Icon(Icons.autorenew),
                    label: const Text('Visite de Contrôle'),
                  ),
                  if (!widget.isHistory)
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                      onPressed: _cloturer,
                      icon: const Icon(Icons.close),
                      label: const Text('Clôturer la visite'),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),
          
          if (isEnAttente) ...[
            const Card(
              color: Colors.orangeAccent,
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    Icon(Icons.hourglass_empty, color: Colors.white),
                    SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        'Le médecin a accepté la visite mais n\'a pas encore soumis son rapport. En attente...',
                        style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    )
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],

          // Doctor Info Section
          _buildCard('Médecin en Charge', [
            Row(
              children: [
                const Icon(Icons.person_pin, color: Colors.blue),
                const SizedBox(width: 8),
                DoctorNameBadge(
                  medecinId: widget.consultation.medecinId,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ]),

          const SizedBox(height: 16),

          // Patient Info Section
          if (_patientData != null)
            _buildCard('Informations Patient', [
              _buildRow('Nom Complet', '${_patientData!['nom']} ${_patientData!['prenom']}'),
              if (_patientData!['dateNaissance'] != null && _patientData!['dateNaissance'].toString().isNotEmpty)
                _buildRow(
                  'Date de Naissance',
                  '${_patientData!['dateNaissance']}' +
                      (_patientData!['age'] != null && _patientData!['age'].toString().isNotEmpty
                          ? ' (${_patientData!['age']})'
                          : ' (${calculateAge(_patientData!['dateNaissance'])})'),
                ),
              if (_patientData!['ville'] != null && _patientData!['ville'].toString().isNotEmpty)
                _buildRow('Origine / Ville', '${_patientData!['ville']}'),
              _buildRow('Hôtel', '${_patientData!['hotel'] ?? 'Non renseigné'}'),
              _buildRow('Garantie / Prise en charge (N° Dossier ELAA)', '${_patientData!['garantie'] ?? _patientData!['dossier'] ?? 'Non renseigné'}'),
              if (_garantieUrl != null && _garantieUrl!.isNotEmpty) ...[
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  onPressed: () => _showDocumentDialog(context, 'Document de Garantie', _garantieUrl!),
                  icon: const Icon(Icons.description),
                  label: const Text('Voir document de Garantie (PDF / Photo)'),
                ),
              ],
            ]),
            
          const SizedBox(height: 16),
          
          // Passport Section
          if (_passportUrl != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Pièce d\'identité', style: Theme.of(context).textTheme.titleLarge),
                    const Divider(),
                    const SizedBox(height: 10),
                    _passportUrl!.startsWith('http')
                        ? Image.network(_passportUrl!, height: 300, fit: BoxFit.contain)
                        : Image.file(File(_passportUrl!), height: 300, fit: BoxFit.contain),
                  ],
                ),
              ),
            ),

          if (_passportUrl != null) const SizedBox(height: 16),

          // Rapport Section
          if (_rapportData != null)
            _buildCard('Rapport Médical', [
              if (_rapportData!['dateActe'] != null && _rapportData!['dateActe'].toString().isNotEmpty)
                _buildRow('Date / Heure', '${_rapportData!['dateActe']} - ${_rapportData!['heureActe'] ?? ''}'),
              if (_rapportData!['partner'] != null && _rapportData!['partner'].toString().isNotEmpty)
                _buildRow('Partenaire associé', _rapportData!['partner']),
              _buildRow('Motif de consultation', _rapportData!['motif']),
              _buildRow('Histoire de la maladie', _rapportData!['histoire']),
              _buildRow('Constantes vitales', 'Poids: ${_rapportData!['poids'] ?? ''} | Taille: ${_rapportData!['taille'] ?? ''} | TA: ${_rapportData!['ta'] ?? ''} | Pouls: ${_rapportData!['pouls'] ?? ''} | Temp: ${_rapportData!['temp'] ?? ''} | SpO2: ${_rapportData!['spo2'] ?? ''}'),
              _buildRow('Examen Général', _rapportData!['examGeneral']),
              if (_rapportData!['examOrl'] != null && _rapportData!['examOrl'].toString().isNotEmpty)
                _buildRow('Examen ORL', _rapportData!['examOrl']),
              if (_rapportData!['examCardio'] != null && _rapportData!['examCardio'].toString().isNotEmpty)
                _buildRow('Cardio-vasculaire', _rapportData!['examCardio']),
              if (_rapportData!['examResp'] != null && _rapportData!['examResp'].toString().isNotEmpty)
                _buildRow('Appareil Respiratoire', _rapportData!['examResp']),
              if (_rapportData!['examAbdo'] != null && _rapportData!['examAbdo'].toString().isNotEmpty)
                _buildRow('Sphère Abdominale', _rapportData!['examAbdo']),
              if (_rapportData!['examNeuro'] != null && _rapportData!['examNeuro'].toString().isNotEmpty)
                _buildRow('Système Nerveux', _rapportData!['examNeuro']),
              if (_rapportData!['examOther'] != null && _rapportData!['examOther'].toString().isNotEmpty)
                _buildRow('Divers / Autres', _rapportData!['examOther']),
              _buildRow('Diagnostic', _rapportData!['diagnostic']),
              _buildRow('Maladie Préexistante', _rapportData!['preexistant']),
              if (_rapportData!['recommandations'] != null && _rapportData!['recommandations'].toString().isNotEmpty)
                _buildRow('Recommandations post-thérapeutiques', _rapportData!['recommandations']),
            ]),
          
          const SizedBox(height: 16),

          // Ordonnance Section
          if (_ordonnance != null && _ordonnance!.isNotEmpty)
            _buildCard('Ordonnance / Plan Thérapeutique', [
              Text(_ordonnance!, style: const TextStyle(fontSize: 16)),
            ]),
            
          const SizedBox(height: 16),
          
          // Finance Section
          if (_financeData != null)
            _buildCard('Rapport Financier - Facturation ELAA', [
              _buildRow('Honoraires (HT)', '${_financeData!['honoraires'] ?? ''} DT'),
              if (_financeData!['tva'] != null && _financeData!['tva'].toString().isNotEmpty)
                _buildRow('Pourcentage TVA (%)', '${_financeData!['tva']}'),
              if (_financeData!['injections'] == true)
                _buildRow('Injections', 'Oui (x${_financeData!['qtyInjections'] ?? 1}) - 14.019 DT/u HT'),
              if (_financeData!['sutures'] == true)
                _buildRow('Points de suture', 'Oui (x${_financeData!['qtySutures'] ?? 1}) - 18.691 DT/u HT'),
              if (_financeData!['soins'] == true)
                _buildRow('Soins locaux / Pansements', 'Oui - 20.000 DT HT'),
              _buildRow('Couverture', '${_financeData!['couverture'] ?? ''}'),
              if (_financeData!['couverture'] == 'Avec Franchise' && _financeData!['franchise'] != null)
                _buildRow('Franchise Patient TTC', '${_financeData!['franchise']} DT'),
              if (_financeData!['totalHT'] != null) ...[
                const Divider(),
                _buildRow('Total HT', '${_financeData!['totalHT']} DT'),
                _buildRow('Montant TVA', '${_financeData!['tvaAmount'] ?? ''} DT'),
                _buildRow('Total TTC', '${_financeData!['totalTTC']} DT'),
                _buildRow('Net à payer par Assurance', '${_financeData!['netAPayer']} DT'),
              ],
              if (_financeData!['docType'] != null && _financeData!['docNum'] != null && _financeData!['docNum'].toString().isNotEmpty)
                _buildRow('Document Facturation', '${_financeData!['docType']} - N° ${_financeData!['docNum']}'),
            ]),
            
          const SizedBox(height: 40),
        ],
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
            Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Theme.of(context).colorScheme.primary)),
            const Divider(),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildRow(String label, String? value) {
    if (value == null || value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text('$label :', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 16))),
        ],
      ),
    );
  }

  Future<Uint8List> _generatePdfBytes(String title, String content) async {
    final pdf = pw.Document();
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Header(
                level: 0,
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('ELAA INTERNATIONAL', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900)),
                    pw.Text('DOCPOCKET PRO HUB', style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey700)),
                  ],
                ),
              ),
              pw.SizedBox(height: 12),
              pw.Text(title, style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
              pw.Divider(thickness: 1.5, color: PdfColors.blue900),
              pw.SizedBox(height: 14),
              pw.Text(content, style: const pw.TextStyle(fontSize: 10, lineSpacing: 1.4)),
              pw.Spacer(),
              pw.Divider(thickness: 0.8, color: PdfColors.grey400),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Document certifié ELAA DocPocket Pro Hub', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
                  pw.Text(DateTime.now().toString().substring(0, 16), style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
                ],
              ),
            ],
          );
        },
      ),
    );
    return pdf.save();
  }

  Future<void> _syncBridgeFiles() async {
    // Sync Passport
    if (_passportUrl != null && _passportUrl!.startsWith('bridge_')) {
      final fileName = _passportUrl!.substring(7); // enlever 'bridge_'
      String? localPath = await LocalBackupService.checkLocalFile(widget.consultation.id, fileName);
      if (localPath == null) {
        localPath = await LocalBackupService.downloadFromBridge(widget.consultation.id, fileName);
        if (localPath != null) {
          await LocalBackupService.deleteFromBridge(widget.consultation.id, fileName);
        }
      }
      if (localPath != null && mounted) {
        setState(() {
          _passportUrl = localPath;
        });
      }
    }

    // Check local Garantie (Le hub l'a déjà téléchargée lors de la création)
    if (_garantieUrl != null && !_garantieUrl!.startsWith('http')) {
      final fileName = _garantieUrl!;
      String? localPath = await LocalBackupService.checkLocalFile(widget.consultation.id, fileName);
      if (localPath != null && mounted) {
        setState(() {
          _garantieUrl = localPath;
        });
      }
    }
  }
}

