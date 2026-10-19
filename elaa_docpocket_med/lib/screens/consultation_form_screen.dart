import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';
import 'package:elaa_shared/elaa_shared.dart';
import '../utils/mail_launcher.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:geolocator/geolocator.dart';

class ConsultationFormScreen extends StatefulWidget {
  final String? consultationId;
  const ConsultationFormScreen({super.key, this.consultationId});

  @override
  State<ConsultationFormScreen> createState() => _ConsultationFormScreenState();
}

class _ConsultationFormScreenState extends State<ConsultationFormScreen> {
  // Démographie
  final _nomController = TextEditingController();
  final _prenomController = TextEditingController();
  final _telController = TextEditingController();
  final _villeController = TextEditingController();
  final _docNumController = TextEditingController();
  final _dossierController = TextEditingController();
  String _docType = 'Passeport';
  
  double _targetLat = 0.0;
  double _targetLng = 0.0;
  
  // Calculate distance in km using Haversine formula
  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    var p = 0.017453292519943295;
    var c = math.cos;
    var a = 0.5 - c((lat2 - lat1) * p) / 2 + 
          c(lat1 * p) * c(lat2 * p) * 
          (1 - c((lon2 - lon1) * p)) / 2;
    return 12742 * math.asin(math.sqrt(a)); 
  }

  Future<void> _showRouteDialog() async {
    double dLat = GpsTrackingService.currentLat;
    double dLng = GpsTrackingService.currentLng;
    
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      ).timeout(const Duration(seconds: 3));
      dLat = position.latitude;
      dLng = position.longitude;
    } catch (_) {}

    final distanceKm = _calculateDistance(dLat, dLng, _targetLat, _targetLng);
    final estimatedTimeMinutes = (distanceKm / 40.0) * 60.0; 

    if (mounted) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Itinéraire estimé'),
          content: Text(
            'L\'hôtel se trouve à ${distanceKm.toStringAsFixed(1)} km.\n\n'
            'Temps estimé : ${estimatedTimeMinutes.toStringAsFixed(0)} minutes.'
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Fermer'),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
              onPressed: () async {
                Navigator.pop(ctx);
                final url = 'https://www.google.com/maps/dir/?api=1&origin=$dLat,$dLng&destination=$_targetLat,$_targetLng';
                try {
                  final uri = Uri.parse(url);
                  if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
                    await launchUrl(uri, mode: LaunchMode.platformDefault);
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Erreur: Impossible d\'ouvrir Google Maps')));
                  }
                }
              },
              icon: const Icon(Icons.map),
              label: const Text('Google Maps'),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade700, foregroundColor: Colors.white),
              onPressed: () async {
                Navigator.pop(ctx);
                final url = 'https://www.openstreetmap.org/directions?engine=fossgis_osrm_car&route=$dLat,$dLng;$_targetLat,$_targetLng';
                try {
                  final uri = Uri.parse(url);
                  if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
                    await launchUrl(uri, mode: LaunchMode.platformDefault);
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Erreur: Impossible d\'ouvrir OpenStreetMap')));
                  }
                }
              },
              icon: const Icon(Icons.explore),
              label: const Text('OpenStreetMap'),
            ),
          ],
        ),
      );
    }
  }
  
  // Clinique
  final _motifController = TextEditingController();
  final _histoireController = TextEditingController();
  final _atcdController = TextEditingController();
  final _allergiesController = TextEditingController();

  // Constantes
  final _poidsController = TextEditingController();
  final _tailleController = TextEditingController();
  final _taController = TextEditingController();
  final _poulsController = TextEditingController();
  final _tempController = TextEditingController();
  final _spo2Controller = TextEditingController();

  // Examen Physique
  final _examGeneralController = TextEditingController();
  final _examOrlController = TextEditingController();
  final _examCardioController = TextEditingController();
  final _examRespController = TextEditingController();
  final _examNeuroController = TextEditingController();
  final _examAbdoController = TextEditingController();
  final _examOtherController = TextEditingController();

  // Temporel & Partenaire
  final _dateActeController = TextEditingController();
  final _heureActeController = TextEditingController();
  final _partnerController = TextEditingController(text: 'ELAA International');

  // Conclusion
  final _diagnosticController = TextEditingController();
  final _ordonnanceController = TextEditingController();
  String _preexistant = 'Non';

  // Facturation
  final _honorairesController = TextEditingController(text: '90.000');
  final _tvaController = TextEditingController(text: '7');
  final _franchiseController = TextEditingController(text: '10.000');
  String _couverture = 'Avec Franchise';
  bool _hasInjections = false;
  int _qtyInjections = 1;
  bool _hasSutures = false;
  int _qtySutures = 1;
  bool _hasSoins = false;

  // Démographie supp
  final _ddnController = TextEditingController();
  final _ageController = TextEditingController();
  final _hotelController = TextEditingController();
  final _chambreController = TextEditingController();
  String? _garantieUrl;

  // Recommandations
  final _recommandationsController = TextEditingController();

  enc.Key? _consultationAesKey;
  Consultation? _consultation;
  
  XFile? _passportImage;
  XFile? _priseEnChargeImage;
  List<XFile> _explorationImages = [];
  bool _isUploading = false;

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked != null) {
      setState(() {
        _passportImage = picked;
      });
    }
  }

  Future<void> _pickPriseEnChargeImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked != null) {
      setState(() {
        _priseEnChargeImage = picked;
      });
    }
  }

  Future<void> _pickExplorationImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked != null) {
      setState(() {
        _explorationImages.add(picked);
      });
    }
  }

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _dateActeController.text = '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';
    _heureActeController.text = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    _ddnController.addListener(() {
      final calculated = calculateAge(_ddnController.text);
      if (_ageController.text != calculated) {
        _ageController.text = calculated;
      }
    });
    _taController.addListener(() {
      final text = _taController.text;
      if (text.length == 3 && !text.contains('/')) {
        _taController.value = TextEditingValue(
          text: '$text/',
          selection: TextSelection.collapsed(offset: 4),
        );
      }
    });
    if (widget.consultationId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadConsultationData();
      });
    }
  }

  Future<String?> _showPinDialog() async {
    String? pin;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) {
        final pc = TextEditingController();
        return AlertDialog(
          title: const Text('Déverrouillage requis'),
          content: TextField(
            controller: pc,
            obscureText: true,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Code PIN personnel'),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(c);
                Navigator.pop(context); // Go back if cancel
              },
              child: const Text('Annuler'),
            ),
            ElevatedButton(
              onPressed: () {
                pin = pc.text;
                Navigator.pop(c);
              },
              child: const Text('Valider'),
            )
          ],
        );
      }
    );
    return pin;
  }

  Future<void> _loadConsultationData() async {
    try {
      final doc = await FirebaseFirestore.instance.collection('consultations').doc(widget.consultationId).get();
      if (!doc.exists) return;
      final rawData = doc.data()!;
      _consultation = Consultation.fromMap(rawData, doc.id);
      _targetLat = (rawData['gpsTargetLat'] as num?)?.toDouble() ?? 0.0;
      _targetLng = (rawData['gpsTargetLng'] as num?)?.toDouble() ?? 0.0;

      final prefs = await SharedPreferences.getInstance();
      final encryptedPrivKey = prefs.getString('encrypted_private_key');
      if (encryptedPrivKey == null) throw Exception('Clé privée introuvable');

      final pin = await _showPinDialog();
      if (pin == null) return;

      final aesKeyFromPin = EncryptionEngine.deriveKeyFromPin(pin, _consultation!.medecinId);
      final privKeyJson = EncryptionEngine.decryptDataAES(encryptedPrivKey, aesKeyFromPin);
      final rsaPrivKey = EncryptionEngine.parsePrivateKeyFromJson(privKeyJson);

      final aesKeyBase64 = EncryptionEngine.decryptRSA(_consultation!.encryptedKeyForMedecin, rsaPrivKey);
      _consultationAesKey = enc.Key.fromBase64(aesKeyBase64);

      if (_consultation!.encryptedPatientData != null) {
        final patientJson = EncryptionEngine.decryptDataAES(_consultation!.encryptedPatientData!, _consultationAesKey!);
        final patientData = jsonDecode(patientJson);
        setState(() {
          _nomController.text = patientData['nom'] ?? '';
          _prenomController.text = patientData['prenom'] ?? '';
          _telController.text = patientData['telephone'] ?? patientData['tel'] ?? '';
          _ddnController.text = patientData['dateNaissance'] ?? '';
          _ageController.text = patientData['age'] ?? calculateAge(_ddnController.text);
          _villeController.text = patientData['ville'] ?? patientData['origine'] ?? '';
          _hotelController.text = patientData['hotel'] ?? '';
          _chambreController.text = patientData['chambre'] ?? '';
          _dossierController.text = patientData['dossier'] ?? patientData['garantie'] ?? '';
          if (patientData['garantieUrl'] != null) {
            _garantieUrl = patientData['garantieUrl'];
          } else if (_consultation!.encryptedGarantieUrl != null) {
            _garantieUrl = EncryptionEngine.decryptDataAES(_consultation!.encryptedGarantieUrl!, _consultationAesKey!);
          }
        });
        
        if (_targetLat == 0.0 && _targetLng == 0.0 && _hotelController.text.isNotEmpty) {
          try {
            final hotelQuery = await FirebaseFirestore.instance.collection('hotels')
                .where('nom', isEqualTo: _hotelController.text.trim())
                .limit(1)
                .get();
            if (hotelQuery.docs.isNotEmpty) {
              setState(() {
                _targetLat = (hotelQuery.docs.first.data()['lat'] as num?)?.toDouble() ?? 0.0;
                _targetLng = (hotelQuery.docs.first.data()['lng'] as num?)?.toDouble() ?? 0.0;
              });
            }
          } catch (_) {}
        }
        
        _syncBridgeFiles();
      }

      if (_consultation!.encryptedDossierMedicalPrive != null) {
        final parts = _consultation!.encryptedDossierMedicalPrive!.split('|');
        if (parts.length == 2) {
          final encPrivAesBase64 = parts[0];
          final encData = parts[1];
          final privateAesKeyBase64 = EncryptionEngine.decryptRSA(encPrivAesBase64, rsaPrivKey);
          final privateAesKey = enc.Key.fromBase64(privateAesKeyBase64);
          final jsonStr = EncryptionEngine.decryptDataAES(encData, privateAesKey);
          final privData = jsonDecode(jsonStr);
          setState(() {
            _atcdController.text = privData['atcd'] ?? '';
            _allergiesController.text = privData['allergies'] ?? '';
          });
        }
      }

      if (_consultation!.encryptedRapport != null) {
        final rapportJson = EncryptionEngine.decryptDataAES(_consultation!.encryptedRapport!, _consultationAesKey!);
        final rapData = jsonDecode(rapportJson);
        setState(() {
          _motifController.text = rapData['motif'] ?? '';
          _histoireController.text = rapData['histoire'] ?? '';
          _poidsController.text = rapData['poids'] ?? '';
          _tailleController.text = rapData['taille'] ?? '';
          _taController.text = rapData['ta'] ?? '';
          _poulsController.text = rapData['pouls'] ?? '';
          _tempController.text = rapData['temp'] ?? '';
          _spo2Controller.text = rapData['spo2'] ?? '';
          _examGeneralController.text = rapData['examGeneral'] ?? '';
          _examOrlController.text = rapData['examOrl'] ?? '';
          _examCardioController.text = rapData['examCardio'] ?? '';
          _examRespController.text = rapData['examResp'] ?? '';
          _examAbdoController.text = rapData['examAbdo'] ?? '';
          _examNeuroController.text = rapData['examNeuro'] ?? '';
          _dateActeController.text = rapData['dateActe'] ?? _dateActeController.text;
          _heureActeController.text = rapData['heureActe'] ?? _heureActeController.text;
          _partnerController.text = rapData['partner'] ?? _partnerController.text;
          _examOtherController.text = rapData['examOther'] ?? '';
          _diagnosticController.text = rapData['diagnostic'] ?? '';
          _preexistant = rapData['preexistant'] ?? 'Non';
          _recommandationsController.text = rapData['recommandations'] ?? '';
        });
      }

      if (_consultation!.encryptedOrdonnance != null) {
        final ordText = EncryptionEngine.decryptDataAES(_consultation!.encryptedOrdonnance!, _consultationAesKey!);
        setState(() {
          _ordonnanceController.text = ordText;
        });
      }

      if (_consultation!.encryptedEtatFinancier != null) {
        final finJson = EncryptionEngine.decryptDataAES(_consultation!.encryptedEtatFinancier!, _consultationAesKey!);
        final finData = jsonDecode(finJson);
        setState(() {
          _honorairesController.text = finData['honoraires'] ?? _honorairesController.text;
          _tvaController.text = finData['tva'] ?? _tvaController.text;
          _couverture = finData['couverture'] ?? _couverture;
          if (finData['injections'] != null) _hasInjections = finData['injections'] == true;
          if (finData['qtyInjections'] != null) _qtyInjections = finData['qtyInjections'];
          if (finData['sutures'] != null) _hasSutures = finData['sutures'] == true;
          if (finData['qtySutures'] != null) _qtySutures = finData['qtySutures'];
          if (finData['soins'] != null) _hasSoins = finData['soins'] == true;
          if (finData['franchise'] != null) _franchiseController.text = finData['franchise'].toString();
        });
      }

      // Load local draft if any
      final draftStr = prefs.getString('local_draft_${widget.consultationId}');
      if (draftStr != null) {
        try {
          final draft = jsonDecode(draftStr);
          setState(() {
            if ((draft['motif'] ?? '').isNotEmpty) _motifController.text = draft['motif'];
            if ((draft['histoire'] ?? '').isNotEmpty) _histoireController.text = draft['histoire'];
            if ((draft['diagnostic'] ?? '').isNotEmpty) _diagnosticController.text = draft['diagnostic'];
            if ((draft['ordonnance'] ?? '').isNotEmpty) _ordonnanceController.text = draft['ordonnance'];
          });
        } catch (_) {}
      }
    } catch (e) {
      if (mounted) {
        String msg = 'Erreur: $e';
        final errStr = e.toString();
        if (errStr.contains('Unsupported block type') || errStr.contains('Invalid argument') || errStr.contains('RSA') || errStr.contains('PKCS')) {
          msg = '⚠️ Clé de sécurité incompatible : Cette consultation a été créée avant la dernière réinitialisation de votre licence sur cet appareil. Veuillez créer une nouvelle demande depuis le Hub.';
        }
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(msg),
          duration: const Duration(seconds: 6),
        ));
        Navigator.pop(context);
      }
    }
  }

  double _parseNum(String s) {
    return double.tryParse(s.replaceAll(',', '.').replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0.0;
  }

  Map<String, double> _calculateTotals() {
    final honoraires = _parseNum(_honorairesController.text);
    final tvaRate = _parseNum(_tvaController.text);
    double actesHT = 0.0;
    if (_hasInjections) actesHT += 14.019 * _qtyInjections;
    if (_hasSutures) actesHT += 18.691 * _qtySutures;
    if (_hasSoins) actesHT += 20.000;
    final totalHT = honoraires + actesHT;
    final tvaAmount = totalHT * (tvaRate / 100.0);
    final totalTTC = totalHT + tvaAmount;
    final franchise = _parseNum(_franchiseController.text);
    double netAPayer = totalTTC;
    if (_couverture == 'Avec Franchise') {
      netAPayer = (totalTTC - franchise) > 0 ? (totalTTC - franchise) : 0.0;
    } else if (_couverture == 'Payant') {
      netAPayer = 0.0;
    }
    return {
      'totalHT': totalHT,
      'tvaAmount': tvaAmount,
      'totalTTC': totalTTC,
      'franchise': franchise,
      'netAPayer': netAPayer,
    };
  }

  Future<void> _saveLocally() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final draftData = {
        'dateActe': _dateActeController.text,
        'heureActe': _heureActeController.text,
        'partner': _partnerController.text,
        'examOther': _examOtherController.text,
        'nom': _nomController.text,
        'prenom': _prenomController.text,
        'tel': _telController.text,
        'motif': _motifController.text,
        'histoire': _histoireController.text,
        'diagnostic': _diagnosticController.text,
        'ordonnance': _ordonnanceController.text,
        'honoraires': _honorairesController.text,
        'tva': _tvaController.text,
        'injections': _hasInjections,
        'qtyInjections': _qtyInjections,
        'sutures': _hasSutures,
        'qtySutures': _qtySutures,
        'soins': _hasSoins,
        'franchise': _franchiseController.text,
        'couverture': _couverture,
      };
      await prefs.setString('local_draft_${widget.consultationId ?? "draft"}', jsonEncode(draftData));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Rapport et ordonnance enregistrés localement sur cet appareil.', style: TextStyle(color: Colors.white)),
          backgroundColor: Colors.green,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur enregistrement local: $e')));
      }
    }
  }

  String _generateRapportMedicalText() {
    return '''
=========================================
  RAPPORT MÉDICAL (Strictement Médical)
     ELAA DocPocket Med - Pro Hub
=========================================
Patient: ${_nomController.text} ${_prenomController.text}
Âge: ${_ageController.text} | Tél: ${_telController.text}
Date de l'acte: ${_dateActeController.text} à ${_heureActeController.text}
Partenaire associé: ${_partnerController.text}

--- EXAMEN CLINIQUE ---
• Motif de consultation : ${_motifController.text}
• Histoire de la maladie : ${_histoireController.text}
• Antécédents médicaux : ${_atcdController.text}
• Allergies connues : ${_allergiesController.text}
• Constantes vitales :
  - Poids : ${_poidsController.text} | Taille : ${_tailleController.text}
  - TA : ${_taController.text} | Pouls : ${_poulsController.text}
  - Température : ${_tempController.text} | SpO2 : ${_spo2Controller.text}
• Examen Général : ${_examGeneralController.text}
• Examen ORL : ${_examOrlController.text}
• Examen Cardiovasculaire : ${_examCardioController.text}
• Examen Pulmonaire : ${_examRespController.text}
• Examen Abdominal : ${_examAbdoController.text}
• Examen Neurologique : ${_examNeuroController.text}
• Divers / Autres : ${_examOtherController.text}

--- DIAGNOSTIC & RECOMMANDATIONS ---
• Diagnostic principal : ${_diagnosticController.text}
• Recommandations post-thérapeutiques : ${_recommandationsController.text}

--- ORDONNANCE MÉDICALE ---
${_ordonnanceController.text}

(Note : Ce rapport médical ne contient aucune donnée financière ou de facturation conformément à la séparation des dossiers.)
''';
  }

  String _generateRapportFinancierText() {
    final totals = _calculateTotals();
    return '''
=========================================
  RAPPORT FINANCIER & NOTE D'HONORAIRES
     ELAA International - Facturation
=========================================
Patient: ${_nomController.text} ${_prenomController.text}
Dossier ID: ${widget.consultationId ?? "N/A"}
Type de Couverture: $_couverture
Date: ${DateTime.now().toString().substring(0, 16)}

--- DÉTAIL DES ACTES ET HONORAIRES (HT) ---
• Honoraires de consultation : ${_honorairesController.text} DT HT
• Injections réalisées : ${_hasInjections ? "Oui (x$_qtyInjections) - 14.019 DT/u HT" : "Non"}
• Points de suture : ${_hasSutures ? "Oui (x$_qtySutures) - 18.691 DT/u HT" : "Non"}
• Soins locaux / Pansements : ${_hasSoins ? "Oui - Forfait 20.000 DT HT" : "Non"}
• Taux de TVA applicable : ${_tvaController.text} %

--- SYNTHÈSE ET PRISES EN CHARGE (TTC) ---
• Total HT : ${totals['totalHT']!.toStringAsFixed(3)} DT
• Montant TVA : ${totals['tvaAmount']!.toStringAsFixed(3)} DT
• TOTAL GÉNÉRAL TTC : ${totals['totalTTC']!.toStringAsFixed(3)} DT
${_couverture == 'Avec Franchise' ? "• Franchise Patient TTC : ${totals['franchise']!.toStringAsFixed(3)} DT\n" : ""}• NET À PAYER PAR L'ASSURANCE : ${totals['netAPayer']!.toStringAsFixed(3)} DT

(Note : Ce rapport financier ne contient aucun diagnostic clinique.)
''';
  }

  Future<void> _sendByMail() async {
    final prefs = await SharedPreferences.getInstance();
    final doctorNom = prefs.getString('medecin_nom') ?? '';
    final doctorPrenom = prefs.getString('medecin_prenom') ?? '';
    final doctorName = '$doctorPrenom $doctorNom'.trim();

    final totals = _calculateTotals();
    final subject = 'Rapport Médical & Rapport Financier - ${_nomController.text} ${_prenomController.text}';
    
    final rapportMedical = _generateRapportMedicalText();
    final rapportFinancier = _generateRapportFinancierText();

    final fullEmailBody = '''
Bonjour,

Voici le rapport médical de ${_prenomController.text} ${_nomController.text}.

Veuillez trouver en pièce jointe le rapport médical en PDF, l'ordonnance en PDF et les autres pièces jointes (Passeport, comptes rendus des explorations, etc.).

Cordialement,
Dr $doctorName
''';

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
                  Icon(Icons.mark_email_read, color: Colors.teal),
                  SizedBox(width: 8),
                  Text('Mail : Rapports & Pièces Jointes'),
                ],
              ),
              SizedBox(height: 12),
              TabBar(
                labelColor: Colors.teal,
                unselectedLabelColor: Colors.grey,
                indicatorColor: Colors.teal,
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
                        decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(4)),
                        child: SingleChildScrollView(child: Text(rapportMedical, style: const TextStyle(fontFamily: 'monospace', fontSize: 12))),
                      ),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(4)),
                        child: SingleChildScrollView(child: Text(rapportFinancier, style: const TextStyle(fontFamily: 'monospace', fontSize: 12))),
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
                          'Les deux rapports sont générés : 1) Rapport Médical PDF (sans honoraires), 2) Rapport Financier PDF (sans diagnostic) + Ordonnance PDF & Pièces jointes.',
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
              onPressed: () => _generateAndPrintPDF('Rapport Médical', rapportMedical),
              icon: const Icon(Icons.picture_as_pdf, size: 16),
              label: const Text('Rapport Médical (PDF)'),
            ),
            TextButton.icon(
              onPressed: () => _generateAndPrintPDF('Rapport Financier', rapportFinancier),
              icon: const Icon(Icons.picture_as_pdf, size: 16),
              label: const Text('Rapport Financier (PDF)'),
            ),
            ElevatedButton.icon(
              onPressed: () async {
                Navigator.pop(ctx);
                _showAttachmentSelectionDialog(subject, fullEmailBody, rapportMedical, rapportFinancier);
              },
              icon: const Icon(Icons.email),
              label: const Text('Ouvrir E-mail & Pièces jointes'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Fermer'),
            ),
          ],
        ),
      ),
    );
  }

  void _showAttachmentSelectionDialog(String subject, String body, String rapportMedical, String rapportFinancier) {
    bool sendRapport = true;
    bool sendOrdonnance = true;
    bool sendIdDoc = true;
    bool sendPriseEnCharge = true;
    bool sendExploration = true;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Choisir les pièces à envoyer par mail'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CheckboxListTile(
                title: const Text('Rapport de consultation (PDF / Text)'),
                value: sendRapport,
                onChanged: (v) => setDialogState(() => sendRapport = v ?? true),
              ),
              CheckboxListTile(
                title: const Text('Ordonnance médicale (PDF / Text)'),
                value: sendOrdonnance,
                onChanged: (v) => setDialogState(() => sendOrdonnance = v ?? true),
              ),
              CheckboxListTile(
                title: const Text('Document d\'identité'),
                value: sendIdDoc,
                onChanged: (v) => setDialogState(() => sendIdDoc = v ?? true),
              ),
              CheckboxListTile(
                title: const Text('Prise en charge'),
                value: sendPriseEnCharge,
                onChanged: (v) => setDialogState(() => sendPriseEnCharge = v ?? true),
              ),
              CheckboxListTile(
                title: const Text('Document d\'exploration'),
                value: sendExploration,
                onChanged: (v) => setDialogState(() => sendExploration = v ?? true),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
            ElevatedButton.icon(
              onPressed: () async {
                Navigator.pop(ctx);
                if (_consultation != null) {
                  await LocalBackupService.saveAutoBackup(
                    consultationId: _consultation!.id,
                    medecinId: _consultation!.medecinId,
                    data: {
                      'patient': {'nom': _nomController.text, 'prenom': _prenomController.text},
                      'rapport': sendRapport ? rapportMedical : null,
                      'finance': sendRapport ? rapportFinancier : null,
                      'ordonnance': sendOrdonnance ? _ordonnanceController.text : null,
                    },
                    isManual: true,
                  );
                }
                try {
                  List<EmailAttachment> attachments = [];
                  final safeNom = _nomController.text.trim().replaceAll(' ', '_');
                  final safePrenom = _prenomController.text.trim().replaceAll(' ', '_');
                  final patientTag = (safeNom.isNotEmpty || safePrenom.isNotEmpty) ? '${safeNom}_$safePrenom' : 'Patient';

                  // 1. Rapport Médical (PDF)
                  if (sendRapport) {
                    final pdfBytes = await _generatePdfBytes('Rapport de Consultation Médicale', rapportMedical);
                    attachments.add(EmailAttachment(
                      filename: 'Rapport_Medical_$patientTag.pdf',
                      bytes: pdfBytes,
                      mimeType: 'application/pdf',
                    ));

                    final financePdfBytes = await _generatePdfBytes('Rapport Financier & Facturation', rapportFinancier);
                    attachments.add(EmailAttachment(
                      filename: 'Rapport_Financier_$patientTag.pdf',
                      bytes: financePdfBytes,
                      mimeType: 'application/pdf',
                    ));
                  }

                  // 2. Ordonnance (PDF)
                  if (sendOrdonnance && _ordonnanceController.text.trim().isNotEmpty) {
                    final ordonnancePdfBytes = await _generatePdfBytes('Ordonnance Médicale', _ordonnanceController.text);
                    attachments.add(EmailAttachment(
                      filename: 'Ordonnance_$patientTag.pdf',
                      bytes: ordonnancePdfBytes,
                      mimeType: 'application/pdf',
                    ));
                  }

                  // 3. Document d'identité (Passeport / CNI)
                  if (sendIdDoc && _passportImage != null) {
                    try {
                      final bytes = await _passportImage!.readAsBytes();
                      final ext = _passportImage!.name.contains('.') ? _passportImage!.name.split('.').last : 'jpg';
                      attachments.add(EmailAttachment(
                        filename: 'Piece_Identite_$patientTag.$ext',
                        bytes: bytes,
                        mimeType: ext.toLowerCase() == 'pdf' ? 'application/pdf' : 'image/jpeg',
                      ));
                    } catch (e) {
                      debugPrint('Erreur lecture pièce identité: $e');
                    }
                  }

                  // 4. Prise en charge / Garantie
                  if (sendPriseEnCharge && _priseEnChargeImage != null) {
                    try {
                      final bytes = await _priseEnChargeImage!.readAsBytes();
                      final ext = _priseEnChargeImage!.name.contains('.') ? _priseEnChargeImage!.name.split('.').last : 'jpg';
                      attachments.add(EmailAttachment(
                        filename: 'Prise_En_Charge_$patientTag.$ext',
                        bytes: bytes,
                        mimeType: ext.toLowerCase() == 'pdf' ? 'application/pdf' : 'image/jpeg',
                      ));
                    } catch (e) {
                      debugPrint('Erreur lecture prise en charge: $e');
                    }
                  }

                  // 5. Explorations cliniques & analyses
                  if (sendExploration && _explorationImages.isNotEmpty) {
                    for (int i = 0; i < _explorationImages.length; i++) {
                      try {
                        final img = _explorationImages[i];
                        final bytes = await img.readAsBytes();
                        final ext = img.name.contains('.') ? img.name.split('.').last : 'jpg';
                        attachments.add(EmailAttachment(
                          filename: 'Analyse_Exploration_${i + 1}_$patientTag.$ext',
                          bytes: bytes,
                          mimeType: ext.toLowerCase() == 'pdf' ? 'application/pdf' : 'image/jpeg',
                        ));
                      } catch (e) {
                        debugPrint('Erreur lecture exploration $i: $e');
                      }
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
                              ? 'Application Mail ouverte avec le rapport, l\'ordonnance et les pièces jointes (${attachments.length} fichiers attachés).'
                              : 'Préparation terminée (${attachments.length} fichiers). Application Mail ouverte.',
                        ),
                        backgroundColor: Colors.teal.shade700,
                      ),
                    );
                  }
                } catch (e) {
                  debugPrint('Erreur préparation et envoi email: $e');
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

  Future<Uint8List> _generatePdfBytes(String title, String content) async {
    final pdf = pw.Document();
    
    // Attempt to load settings
    final prefs = await SharedPreferences.getInstance();
    final logoBase64 = prefs.getString('settings_logo');
    final ordonnanceBase64 = prefs.getString('settings_ordonnance');
    final tamponBase64 = prefs.getString('settings_tampon');
    
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              if (ordonnanceBase64 != null)
                pw.Center(child: pw.Image(pw.MemoryImage(base64Decode(ordonnanceBase64)), height: 80))
              else if (logoBase64 != null)
                pw.Center(child: pw.Image(pw.MemoryImage(base64Decode(logoBase64)), height: 60)),
              
              pw.SizedBox(height: 20),
              pw.Text(title, style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 20),
              pw.Text(content, style: const pw.TextStyle(fontSize: 12)),
              pw.Spacer(),
              
              if (tamponBase64 != null)
                pw.Align(
                  alignment: pw.Alignment.bottomRight,
                  child: pw.Image(pw.MemoryImage(base64Decode(tamponBase64)), height: 80),
                ),
            ],
          );
        },
      ),
    );
    return pdf.save();
  }

  Future<void> _generateAndPrintPDF(String title, String content) async {
    final pdf = pw.Document();
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(title, style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 20),
              pw.Text(content, style: const pw.TextStyle(fontSize: 12)),
            ],
          );
        },
      ),
    );
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
    );
  }

  Future<void> _sendToElaaRo() async {
    if (_consultationAesKey == null || _consultation == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Impossible de sauvegarder: Clé AES manquante.')));
      return;
    }

    try {
      setState(() => _isUploading = true);

      String? passportUrl;
      if (_passportImage != null) {
        try {
          final bytes = await _passportImage!.readAsBytes();
          passportUrl = await LocalBackupService.uploadToBridge(_consultation!.id, 'passport.jpg', bytes);
          passportUrl = 'bridge_$passportUrl'; 
        } catch (e) {
          throw Exception('Erreur passport upload: $e');
        }
      }

      // Shared Report
      final rapportData = {
        'dateActe': _dateActeController.text,
        'heureActe': _heureActeController.text,
        'partner': _partnerController.text,
        'motif': _motifController.text,
        'histoire': _histoireController.text,
        'poids': _poidsController.text,
        'taille': _tailleController.text,
        'ta': _taController.text,
        'pouls': _poulsController.text,
        'temp': _tempController.text,
        'spo2': _spo2Controller.text,
        'examGeneral': _examGeneralController.text,
        'examOrl': _examOrlController.text,
        'examCardio': _examCardioController.text,
        'examResp': _examRespController.text,
        'examAbdo': _examAbdoController.text,
        'examNeuro': _examNeuroController.text,
        'examOther': _examOtherController.text,
        'diagnostic': _diagnosticController.text,
        'preexistant': _preexistant,
        'recommandations': _recommandationsController.text,
      };
      final encryptedRapport = EncryptionEngine.encryptDataAES(jsonEncode(rapportData), _consultationAesKey!);

      // Shared Ordonnance
      final encryptedOrdonnance = EncryptionEngine.encryptDataAES(_ordonnanceController.text, _consultationAesKey!);

      // Facturation
      final totals = _calculateTotals();
      final financeData = {
        'honoraires': _honorairesController.text,
        'tva': _tvaController.text,
        'couverture': _couverture,
        'docType': _docType,
        'docNum': _docNumController.text,
        'injections': _hasInjections,
        'qtyInjections': _qtyInjections,
        'sutures': _hasSutures,
        'qtySutures': _qtySutures,
        'soins': _hasSoins,
        'franchise': _franchiseController.text,
        'totalHT': totals['totalHT']!.toStringAsFixed(3),
        'tvaAmount': totals['tvaAmount']!.toStringAsFixed(3),
        'totalTTC': totals['totalTTC']!.toStringAsFixed(3),
        'netAPayer': totals['netAPayer']!.toStringAsFixed(3),
      };
      final encryptedEtatFinancier = EncryptionEngine.encryptDataAES(jsonEncode(financeData), _consultationAesKey!);

      // Private Notes
      String? medPubKeyBase64;
      try {
        final doc = await FirebaseFirestore.instance.collection('medecins').doc(_consultation!.medecinId).get();
        if (doc.exists && doc.data() != null) {
          final med = Medecin.fromMap(doc.data()!, doc.id);
          medPubKeyBase64 = med.publicKeyBase64;
        }
      } catch (e) {
        debugPrint('Erreur lecture medecin pour clé RSA: $e');
      }
      if (medPubKeyBase64 == null || medPubKeyBase64.isEmpty) {
        final rsaPair = EncryptionEngine.generateRSAKeyPair();
        final pubMap = {
          'modulus': rsaPair.publicKey.modulus.toString(),
          'exponent': rsaPair.publicKey.exponent.toString(),
        };
        medPubKeyBase64 = base64Encode(utf8.encode(jsonEncode(pubMap)));
        try {
          await FirebaseFirestore.instance.collection('medecins').doc(_consultation!.medecinId).update({
            'publicKeyBase64': medPubKeyBase64,
          });
        } catch (_) {}
      }
      final rsaPubKey = EncryptionEngine.parsePublicKeyFromBase64(medPubKeyBase64);

      final privateData = {
        'atcd': _atcdController.text,
        'allergies': _allergiesController.text,
      };
      
      final privateAesKey = EncryptionEngine.generateConsultationKey();
      final encryptedDossier = EncryptionEngine.encryptDataAES(jsonEncode(privateData), privateAesKey);
      final encPrivAes = EncryptionEngine.encryptRSA(privateAesKey.base64, rsaPubKey);
      final finalEncryptedDossierMedicalPrive = '$encPrivAes|$encryptedDossier';

      final formattedNom = formatNom(_nomController.text);
      final formattedPrenom = formatCapitalized(_prenomController.text);
      final formattedVille = formatCapitalized(_villeController.text);
      final formattedHotel = formatCapitalized(_hotelController.text);

      // Re-encrypt updated patient data
      final patientDataMap = {
        'nom': formattedNom,
        'prenom': formattedPrenom,
        'telephone': _telController.text,
        'dateNaissance': _ddnController.text,
        'age': _ageController.text,
        'ville': formattedVille,
        'hotel': formattedHotel,
        'chambre': _chambreController.text,
        'dossier': _dossierController.text,
        'garantie': _dossierController.text,
        if (_garantieUrl != null) 'garantieUrl': _garantieUrl,
      };
      final updatedEncryptedPatientData = EncryptionEngine.encryptDataAES(jsonEncode(patientDataMap), _consultationAesKey!);

      // Update Firestore
      final updateData = <String, dynamic>{
        'encryptedPatientData': updatedEncryptedPatientData,
        'encryptedRapport': encryptedRapport,
        'encryptedOrdonnance': encryptedOrdonnance,
        'encryptedEtatFinancier': encryptedEtatFinancier,
        'encryptedDossierMedicalPrive': finalEncryptedDossierMedicalPrive,
        'statut': 'Terminée - RO', // Statut transmis au Hub
        'patientNom': formattedNom,
        'patientPrenom': formattedPrenom,
      };

      if (passportUrl != null) {
        updateData['encryptedPassportUrl'] = EncryptionEngine.encryptDataAES(passportUrl, _consultationAesKey!);
      }

      try {
        await FirebaseFirestore.instance.collection('consultations').doc(_consultation!.id).update(updateData);
      } catch (e) {
        throw Exception('Erreur FirebaseFirestore update: $e');
      }

      try {
        await LocalBackupService.saveAutoBackup(
          consultationId: _consultation!.id,
          medecinId: _consultation!.medecinId,
          data: {
            'patient': patientDataMap,
            'rapport': rapportData,
            'finance': financeData,
            'ordonnance': _ordonnanceController.text,
          },
          isManual: true,
        );
      } catch (e) {
        throw Exception('Erreur saveAutoBackup: $e');
      }

      if (mounted) {
        setState(() => _isUploading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Consultation sauvegardée chiffrée & archivée localement.'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isUploading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur sauvegarde: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rapport Médical - ELAA International'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(icon: const Icon(Icons.save), onPressed: _saveLocally),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Informations Temporelles
            _buildSectionTitle('Informations Temporelles'),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Row(
                  children: [
                    Expanded(child: TextField(controller: _dateActeController, decoration: const InputDecoration(labelText: 'Date de l\'acte (JJ/MM/AAAA)'))),
                    const SizedBox(width: 12),
                    Expanded(child: TextField(controller: _heureActeController, decoration: const InputDecoration(labelText: 'Heure de l\'acte (HH:mm)'))),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 2. Démographie
            _buildSectionTitle('Démographie & Gestion Administrative'),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  children: [
                    TextField(
                      controller: _nomController,
                      decoration: const InputDecoration(labelText: 'Nom'),
                      inputFormatters: [UpperCaseTextFormatter()],
                    ),
                    TextField(
                      controller: _prenomController,
                      decoration: const InputDecoration(labelText: 'Prénom'),
                      inputFormatters: [CapitalizeWordsTextFormatter()],
                    ),
                    TextField(controller: _telController, decoration: const InputDecoration(labelText: 'Téléphone'), keyboardType: TextInputType.phone),
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: TextField(
                            controller: _ddnController,
                            decoration: const InputDecoration(labelText: 'Date de Naissance (JJ/MM/AAAA)'),
                            keyboardType: TextInputType.number,
                            inputFormatters: [DateOfBirthFormatter()],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 1,
                          child: TextField(
                            controller: _ageController,
                            readOnly: true,
                            decoration: const InputDecoration(labelText: 'Âge', filled: true),
                          ),
                        ),
                      ],
                    ),
                    TextField(
                      controller: _villeController,
                      decoration: const InputDecoration(labelText: 'Origine / Ville'),
                      inputFormatters: [CapitalizeWordsTextFormatter()],
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _hotelController,
                            decoration: const InputDecoration(labelText: 'Hôtel / Lieu'),
                            inputFormatters: [CapitalizeWordsTextFormatter()],
                          ),
                        ),
                        if (_targetLat != 0.0 && _targetLng != 0.0)
                          IconButton(
                            icon: const Icon(Icons.map, color: Colors.blue),
                            tooltip: 'Voir sur la carte',
                            onPressed: _showRouteDialog,
                          ),
                      ],
                    ),
                    TextField(controller: _chambreController, decoration: const InputDecoration(labelText: 'Chambre N°')),
                    if (_garantieUrl != null && _garantieUrl!.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      ElevatedButton.icon(
                        onPressed: () => _showDocumentDialog(context, 'Document de Garantie', _garantieUrl!),
                        icon: const Icon(Icons.description),
                        label: const Text('Voir le document de Garantie (PDF / Photo)'),
                      ),
                    ],
                    DropdownButtonFormField<String>(
                      value: _docType,
                      items: ['Passeport', 'CIN', 'Carte de Séjour', 'Autre'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                      onChanged: (v) => setState(() => _docType = v!),
                      decoration: const InputDecoration(labelText: 'Type de pièce'),
                    ),
                    TextField(controller: _docNumController, decoration: const InputDecoration(labelText: 'N° de pièce')),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        ElevatedButton.icon(
                          onPressed: _pickImage,
                          icon: const Icon(Icons.camera_alt),
                          label: const Text('Uploader Photo Pièce d\'identité'),
                        ),
                        if (_passportImage != null)
                          const Padding(
                            padding: EdgeInsets.only(left: 8.0),
                            child: Icon(Icons.check_circle, color: Colors.green),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextField(controller: _dossierController, decoration: const InputDecoration(labelText: 'N° du dossier ELAA')),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        ElevatedButton.icon(
                          onPressed: _pickPriseEnChargeImage,
                          icon: const Icon(Icons.attach_file),
                          label: const Text('Joindre Prise en charge'),
                        ),
                        const SizedBox(width: 10),
                        if (_priseEnChargeImage != null)
                          const Icon(Icons.check_circle, color: Colors.green),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Clinique
            _buildSectionTitle('Clinique & Terrain'),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  children: [
                    TextField(controller: _motifController, decoration: const InputDecoration(labelText: 'Motif de consultation *')),
                    TextField(controller: _histoireController, decoration: const InputDecoration(labelText: 'Histoire de la maladie'), maxLines: 3),
                    TextField(controller: _atcdController, decoration: const InputDecoration(labelText: 'Antécédents (ATCD)'), maxLines: 2),
                    TextField(controller: _allergiesController, decoration: const InputDecoration(labelText: 'Allergies & Intolérances')),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 4. Explorations Cliniques
            _buildSectionTitle('📸 Explorations Cliniques (Pièces Jointes)'),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _pickImage,
                            icon: const Icon(Icons.camera_alt),
                            label: const Text('📸 Photo'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _pickImage,
                            icon: const Icon(Icons.folder),
                            label: const Text('📁 Image ou PDF'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (_passportImage != null)
                      const Text('Pièce jointe sélectionnée (prête pour l\'envoi)', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 5. Constantes
            _buildSectionTitle('Constantes Vitales & Biométrie'),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _buildSmallField(_poidsController, 'Poids (kg)'),
                    _buildSmallField(_tailleController, 'Taille (cm)'),
                    _buildSmallField(_taController, 'TA (ex: 120/70)'),
                    _buildSmallField(_poulsController, 'Pouls (bpm)'),
                    _buildSmallField(_tempController, 'Température'),
                    _buildSmallField(_spo2Controller, 'SpO2 (%)'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 6. Examen Physique
            _buildSectionTitle('Examen Physique Systématique'),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  children: [
                    TextField(controller: _examGeneralController, decoration: const InputDecoration(labelText: 'Plan Général')),
                    TextField(controller: _examOrlController, decoration: const InputDecoration(labelText: 'Examen ORL')),
                    TextField(controller: _examCardioController, decoration: const InputDecoration(labelText: 'Cardio-vasculaire')),
                    TextField(controller: _examRespController, decoration: const InputDecoration(labelText: 'Appareil Respiratoire')),
                    TextField(controller: _examAbdoController, decoration: const InputDecoration(labelText: 'Sphère Abdominale')),
                    TextField(controller: _examNeuroController, decoration: const InputDecoration(labelText: 'Système Nerveux')),
                    TextField(controller: _examOtherController, decoration: const InputDecoration(labelText: 'Divers / Autres')),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Conclusion
            _buildSectionTitle('Conclusion Médicale & Prise en Charge'),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(controller: _diagnosticController, decoration: const InputDecoration(labelText: 'Diagnostic')),
                    const SizedBox(height: 10),
                    const Text('Est-ce qu\'il s\'agit d\'une maladie préexistante ?', style: TextStyle(fontWeight: FontWeight.bold)),
                    Row(
                      children: [
                        Radio<String>(value: 'Oui', groupValue: _preexistant, onChanged: (v) => setState(() => _preexistant = v!)),
                        const Text('Oui'),
                        Radio<String>(value: 'Non', groupValue: _preexistant, onChanged: (v) => setState(() => _preexistant = v!)),
                        const Text('Non'),
                      ],
                    ),
                    TextField(controller: _ordonnanceController, decoration: const InputDecoration(labelText: 'Plan Thérapeutique / Ordonnance'), maxLines: 4),
                    const SizedBox(height: 10),
                    TextField(controller: _recommandationsController, decoration: const InputDecoration(labelText: 'Recommandation'), maxLines: 3),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Facturation
            _buildSectionTitle('Facturation Conventionnelle & Couverture Assurantielle'),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: _honorairesController,
                      decoration: const InputDecoration(labelText: 'Honoraires de base HT (DT)'),
                      onChanged: (_) => setState(() {}),
                    ),
                    TextField(
                      controller: _tvaController,
                      decoration: const InputDecoration(labelText: 'Pourcentage TVA (%) (défaut 7%)'),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 12),
                    const Text('Actes Médicaux Spécifiques :', style: TextStyle(fontWeight: FontWeight.bold)),
                    CheckboxListTile(
                      title: const Text('Injections (14.019 DT HT / unité)'),
                      value: _hasInjections,
                      onChanged: (val) => setState(() => _hasInjections = val ?? false),
                    ),
                    if (_hasInjections)
                      Padding(
                        padding: const EdgeInsets.only(left: 16.0, bottom: 8.0),
                        child: Row(
                          children: [
                            const Text('Quantité : '),
                            DropdownButton<int>(
                              value: _qtyInjections,
                              items: [1, 2, 3, 4, 5].map((e) => DropdownMenuItem(value: e, child: Text('$e'))).toList(),
                              onChanged: (v) => setState(() => _qtyInjections = v!),
                            ),
                          ],
                        ),
                      ),
                    CheckboxListTile(
                      title: const Text('Points de suture (18.691 DT HT / unité)'),
                      value: _hasSutures,
                      onChanged: (val) => setState(() => _hasSutures = val ?? false),
                    ),
                    if (_hasSutures)
                      Padding(
                        padding: const EdgeInsets.only(left: 16.0, bottom: 8.0),
                        child: Row(
                          children: [
                            const Text('Quantité : '),
                            DropdownButton<int>(
                              value: _qtySutures,
                              items: [1, 2, 3, 4, 5].map((e) => DropdownMenuItem(value: e, child: Text('$e'))).toList(),
                              onChanged: (v) => setState(() => _qtySutures = v!),
                            ),
                          ],
                        ),
                      ),
                    CheckboxListTile(
                      title: const Text('Soins locaux / Pansements (20.000 DT HT)'),
                      value: _hasSoins,
                      onChanged: (val) => setState(() => _hasSoins = val ?? false),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: _couverture,
                      items: ['Payant', 'Sans Franchise', 'Avec Franchise'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                      onChanged: (v) => setState(() => _couverture = v!),
                      decoration: const InputDecoration(labelText: 'Nature de la couverture'),
                    ),
                    if (_couverture == 'Avec Franchise')
                      Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: TextField(
                          controller: _franchiseController,
                          decoration: const InputDecoration(labelText: 'Montant Franchise Patient TTC (DT)'),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                    _buildFinancialSummary(),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () => _generateAndPrintPDF('Rapport Médical', _generateRapportMedicalText()),
                            icon: const Icon(Icons.picture_as_pdf, color: Colors.white),
                            label: const Text('Rapport Médical (PDF)', textAlign: TextAlign.center),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue.shade700,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () => _generateAndPrintPDF('Rapport Financier', _generateRapportFinancierText()),
                            icon: const Icon(Icons.picture_as_pdf, color: Colors.white),
                            label: const Text('Honoraires (PDF)', textAlign: TextAlign.center),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange.shade800,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _saveLocally,
                    icon: const Icon(Icons.save_alt),
                    label: const Text('Enregistrer localement', textAlign: TextAlign.center),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueGrey,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _sendByMail,
                    icon: const Icon(Icons.mail),
                    label: const Text('Mail', textAlign: TextAlign.center),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isUploading ? null : _sendToElaaRo,
                    icon: _isUploading
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Icon(Icons.send),
                    label: const Text('ELAA RO', textAlign: TextAlign.center),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue.shade800,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildFinancialSummary() {
    final totals = _calculateTotals();
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blueGrey.shade50,
        border: Border.all(color: Colors.blueGrey.shade200),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Récapitulatif Financier (Temps Réel)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const Divider(),
          _buildTotalRow('Total Actes & Honoraires HT :', '${totals['totalHT']!.toStringAsFixed(3)} DT'),
          _buildTotalRow('Montant TVA (${_tvaController.text}) :', '${totals['tvaAmount']!.toStringAsFixed(3)} DT'),
          _buildTotalRow('Total TTC :', '${totals['totalTTC']!.toStringAsFixed(3)} DT', isBold: true),
          if (_couverture == 'Avec Franchise')
            _buildTotalRow('Franchise Patient TTC :', '${totals['franchise']!.toStringAsFixed(3)} DT', color: Colors.orange.shade800),
          _buildTotalRow('Net à payer :', '${totals['netAPayer']!.toStringAsFixed(3)} DT', isBold: true, color: Colors.green.shade800),
        ],
      ),
    );
  }

  Widget _buildTotalRow(String label, String value, {bool isBold = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontWeight: isBold ? FontWeight.bold : FontWeight.normal, color: color)),
          Text(value, style: TextStyle(fontWeight: isBold ? FontWeight.bold : FontWeight.normal, color: color)),
        ],
      ),
    );
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
                child: _buildDocumentContent(url),
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

  Widget _buildDocumentContent(String url) {
    if (url.startsWith('data:image/')) {
      try {
        final base64String = url.split(',').last;
        final bytes = base64Decode(base64String);
        return Image.memory(bytes, fit: BoxFit.contain);
      } catch (e) {
        return _buildErrorFallback(url);
      }
    } else if (url.startsWith('data:application/pdf') || url.toLowerCase().endsWith('.pdf')) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.picture_as_pdf, size: 80, color: Colors.red),
            const SizedBox(height: 16),
            const Text(
              'Document PDF (Garantie de prise en charge)',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () {
                if (url.startsWith('data:application/pdf')) {
                  final base64String = url.split(',').last;
                  final bytes = base64Decode(base64String);
                  downloadWebFile(bytes, 'garantie.pdf', 'application/pdf');
                } else if (!kIsWeb) {
                  launchUrl(Uri.file(url));
                }
              },
              icon: const Icon(Icons.download),
              label: const Text('Télécharger / Consulter le PDF'),
            ),
          ],
        ),
      );
    } else if (url.startsWith('http')) {
      return Image.network(
        url,
        fit: BoxFit.contain,
        errorBuilder: (ctx, err, stack) => _buildErrorFallback(url),
      );
    } else if (!kIsWeb) {
      try {
        final file = File(url);
        if (file.existsSync()) {
          final lower = url.toLowerCase();
          if (lower.endsWith('.png') || lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
            return Image.file(file, fit: BoxFit.contain);
          }
        }
      } catch (_) {}
    }
    return _buildErrorFallback(url);
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

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0, left: 4.0),
      child: Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary)),
    );
  }

  Widget _buildSmallField(TextEditingController controller, String label) {
    return SizedBox(
      width: 150,
      child: TextField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
      ),
    );
  }

  Future<void> _syncBridgeFiles() async {
    if (_garantieUrl != null && !_garantieUrl!.startsWith('http')) {
      final fileName = _garantieUrl!;
      String? localPath = await LocalBackupService.checkLocalFile(_consultation!.id, fileName);
      if (localPath == null) {
        localPath = await LocalBackupService.downloadFromBridge(_consultation!.id, fileName);
        if (localPath != null) {
          await LocalBackupService.deleteFromBridge(_consultation!.id, fileName);
        }
      }
      if (localPath != null && mounted) {
        setState(() {
          _garantieUrl = localPath;
        });
      }
    }
  }
}
