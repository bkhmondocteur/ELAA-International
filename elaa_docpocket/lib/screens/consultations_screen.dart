import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:elaa_shared/elaa_shared.dart';
import 'package:elaa_docpocket/hub_security_manager.dart';
import 'active_consultation_view.dart';
import '../doctor_name_badge.dart';
import '../utils/universal_file_picker.dart';

class ConsultationsScreen extends StatefulWidget {
  const ConsultationsScreen({super.key});

  @override
  State<ConsultationsScreen> createState() => _ConsultationsScreenState();
}

class _ConsultationsScreenState extends State<ConsultationsScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  void _showCreateConsultationDialog() async {
    final nomController = TextEditingController();
    final prenomController = TextEditingController();
    final ddnController = TextEditingController();
    final ageController = TextEditingController();
    final villeController = TextEditingController();
    final hotelController = TextEditingController();
    final gpsController = TextEditingController();
    final chambreController = TextEditingController();
    final garantieController = TextEditingController();
    String? selectedMedecinId;
    List<Medecin> activeMedecins = [];
    List<Map<String, dynamic>> savedHotels = [];
    PlatformFile? selectedGarantieFile;
    bool isUploading = false;

    ddnController.addListener(() {
      final calculated = calculateAge(ddnController.text);
      if (ageController.text != calculated) {
        ageController.text = calculated;
      }
    });

    // Fetch active doctors
    try {
      final snap = await _firestore.collection('medecins').get();
      activeMedecins = snap.docs
          .map((doc) => Medecin.fromMap(doc.data(), doc.id))
          .where((m) => m.statut == 'Actif' || m.statut == 'Conventionné')
          .toList();

      final hotelSnap = await _firestore.collection('hotels').get();
      savedHotels = hotelSnap.docs.map((doc) => doc.data()).toList();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur récupération médecins: $e')));
      }
      return;
    }

    if (!mounted) return;

    if (activeMedecins.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Aucun médecin actif disponible (Licence non activée).')));
      return;
    }

    selectedMedecinId = activeMedecins.first.id;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Nouvelle Demande de Visite Médicale'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nomController,
                      decoration: const InputDecoration(labelText: 'Nom du Patient'),
                      inputFormatters: [UpperCaseTextFormatter()],
                    ),
                    TextField(
                      controller: prenomController,
                      decoration: const InputDecoration(labelText: 'Prénom du Patient'),
                      inputFormatters: [CapitalizeWordsTextFormatter()],
                    ),
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: TextField(
                            controller: ddnController,
                            decoration: const InputDecoration(labelText: 'Date de Naissance (JJ/MM/AAAA)'),
                            keyboardType: TextInputType.number,
                            inputFormatters: [DateOfBirthFormatter()],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 1,
                          child: TextField(
                            controller: ageController,
                            readOnly: true,
                            decoration: const InputDecoration(labelText: 'Âge (calculé)', filled: true),
                          ),
                        ),
                      ],
                    ),
                    TextField(
                      controller: villeController,
                      decoration: const InputDecoration(labelText: 'Origine / Ville'),
                      inputFormatters: [CapitalizeWordsTextFormatter()],
                    ),
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: Autocomplete<Map<String, dynamic>>(
                            optionsBuilder: (TextEditingValue textEditingValue) {
                              if (textEditingValue.text.isEmpty) {
                                return const Iterable<Map<String, dynamic>>.empty();
                              }
                              return savedHotels.where((Map<String, dynamic> option) {
                                final name = (option['nom'] as String?) ?? '';
                                return name.toLowerCase().contains(textEditingValue.text.toLowerCase());
                              });
                            },
                            displayStringForOption: (Map<String, dynamic> option) => option['nom'] as String? ?? '',
                            onSelected: (Map<String, dynamic> selection) {
                              hotelController.text = selection['nom'] as String? ?? '';
                              final lat = selection['lat'];
                              final lng = selection['lng'];
                              if (lat != null && lng != null) {
                                gpsController.text = '$lat, $lng';
                              }
                            },
                            fieldViewBuilder: (BuildContext context, TextEditingController fieldTextEditingController, FocusNode fieldFocusNode, VoidCallback onFieldSubmitted) {
                              // Synchronize inner controller with ours
                              fieldTextEditingController.addListener(() {
                                hotelController.text = fieldTextEditingController.text;
                              });
                              return TextField(
                                controller: fieldTextEditingController,
                                focusNode: fieldFocusNode,
                                decoration: const InputDecoration(labelText: 'Hôtel / Lieu (Recherche ou libre)'),
                                inputFormatters: [CapitalizeWordsTextFormatter()],
                              );
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 1,
                          child: TextField(
                            controller: gpsController,
                            decoration: const InputDecoration(labelText: 'GPS (Lat, Lng)'),
                          ),
                        ),
                      ],
                    ),
                    TextField(controller: chambreController, decoration: const InputDecoration(labelText: 'Numéro de Chambre')),
                    TextField(controller: garantieController, decoration: const InputDecoration(labelText: 'Garantie de Paiement (Ref)')),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              try {
                                final file = await pickSingleFile(
                                  allowedExtensions: ['pdf', 'png', 'jpg', 'jpeg'],
                                  dialogTitle: 'Sélectionner la Garantie de paiement',
                                );
                                if (file != null) {
                                  setDialogState(() {
                                    selectedGarantieFile = file;
                                  });
                                }
                              } catch (e2) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Erreur sélection fichier: $e2'),
                                      backgroundColor: Colors.red,
                                    ),
                                  );
                                }
                              }
                            },
                            icon: const Icon(Icons.attach_file),
                            label: Text(
                              selectedGarantieFile != null
                                  ? 'Garantie: ${selectedGarantieFile!.name}'
                                  : 'Joindre Garantie (PDF / Photo)',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        if (selectedGarantieFile != null) ...[
                          const SizedBox(width: 8),
                          const Icon(Icons.check_circle, color: Colors.green),
                        ],
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Text('Médecin assigné:'),
                    DropdownButtonFormField<String>(
                      value: selectedMedecinId,
                      items: activeMedecins.map((med) {
                        return DropdownMenuItem(value: med.id, child: Text('Dr. ${med.nom} - ${med.specialite}'));
                      }).toList(),
                      onChanged: (val) {
                        setDialogState(() {
                          selectedMedecinId = val;
                        });
                      },
                      decoration: const InputDecoration(labelText: 'Sélectionner un médecin'),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isUploading ? null : () => Navigator.pop(context),
                  child: const Text('Annuler'),
                ),
                ElevatedButton(
                  onPressed: isUploading
                      ? null
                      : () async {
                          setDialogState(() {
                            isUploading = true;
                          });
                          try {
                            final selectedMed = activeMedecins.firstWhere((m) => m.id == selectedMedecinId);

                            var medPubKeyBase64 = selectedMed.publicKeyBase64;
                            // Récupération en temps réel de la clé publique la plus récente
                            try {
                              final freshDoc = await _firestore.collection('medecins').doc(selectedMed.id).get();
                              if (freshDoc.exists && freshDoc.data() != null) {
                                final freshKey = freshDoc.data()!['publicKeyBase64'] as String?;
                                if (freshKey != null && freshKey.isNotEmpty) {
                                  medPubKeyBase64 = freshKey;
                                }
                              }
                            } catch (_) {}

                            if (medPubKeyBase64 == null || medPubKeyBase64.isEmpty) {
                              final rsaPair = EncryptionEngine.generateRSAKeyPair();
                              final pubMap = {
                                'modulus': rsaPair.publicKey.modulus.toString(),
                                'exponent': rsaPair.publicKey.exponent.toString(),
                              };
                              medPubKeyBase64 = base64Encode(utf8.encode(jsonEncode(pubMap)));
                              await _firestore.collection('medecins').doc(selectedMed.id).update({
                                'publicKeyBase64': medPubKeyBase64,
                              });
                            }

                            final docRef = _firestore.collection('consultations').doc();
                            final consId = docRef.id;

                            String? garantieUrl;
                            if (selectedGarantieFile != null) {
                              Uint8List? fileBytes = selectedGarantieFile!.bytes;
                              if (fileBytes == null && selectedGarantieFile!.path != null && !kIsWeb) {
                                fileBytes = File(selectedGarantieFile!.path!).readAsBytesSync();
                              }
                              if (fileBytes != null) {
                                final ext = selectedGarantieFile!.extension ??
                                    (selectedGarantieFile!.name.contains('.')
                                        ? selectedGarantieFile!.name.split('.').last
                                        : 'pdf');
                                garantieUrl = await LocalBackupService.uploadToBridge(consId, 'garantie.$ext', fileBytes)
                                    .timeout(const Duration(seconds: 30));
                              }
                            }

                            final formattedNom = formatNom(nomController.text);
                            final formattedPrenom = formatCapitalized(prenomController.text);
                            final formattedVille = formatCapitalized(villeController.text);
                            final formattedHotel = formatCapitalized(hotelController.text);

                            // 1. Prepare JSON Data
                            final patientData = {
                              'nom': formattedNom,
                              'prenom': formattedPrenom,
                              'dateNaissance': ddnController.text,
                              'age': ageController.text,
                              'ville': formattedVille,
                              'hotel': formattedHotel,
                              'chambre': chambreController.text,
                              'garantie': garantieController.text,
                              if (garantieUrl != null) 'garantieUrl': garantieUrl,
                            };
                            final patientJson = jsonEncode(patientData);

                            // 2. Generate AES Consultation Key
                            final aesKey = EncryptionEngine.generateConsultationKey();

                            // 3. Encrypt Patient JSON with AES
                            final encryptedPatientData = EncryptionEngine.encryptDataAES(patientJson, aesKey);

                            String? encryptedGarantieUrl;
                            if (garantieUrl != null) {
                              encryptedGarantieUrl = EncryptionEngine.encryptDataAES(garantieUrl, aesKey);
                            }

                            // 4. Encrypt AES Key with Hub RSA and Med RSA
                            final medPublicKey = EncryptionEngine.parsePublicKeyFromBase64(medPubKeyBase64);
                            final hubPublicKey = await HubSecurityManager.getPublicKey();

                            final encryptedKeyForMedecin = EncryptionEngine.encryptRSA(aesKey.base64, medPublicKey);
                            final encryptedKeyForHub = EncryptionEngine.encryptRSA(aesKey.base64, hubPublicKey);

                            // 5. Parse GPS and save Hotel if new
                            double? tLat;
                            double? tLng;
                            if (gpsController.text.isNotEmpty) {
                              final parts = gpsController.text.split(',');
                              if (parts.length >= 2) {
                                tLat = double.tryParse(parts[0].trim());
                                tLng = double.tryParse(parts[1].trim());
                              }
                            }
                            
                            if (formattedHotel.isNotEmpty && tLat != null && tLng != null) {
                              final hotelName = formattedHotel;
                              final exists = savedHotels.any((h) => h['nom'] == hotelName);
                              if (!exists) {
                                await _firestore.collection('hotels').add({
                                  'nom': hotelName,
                                  'lat': tLat,
                                  'lng': tLng,
                                });
                              }
                            }

                            // 6. Create Consultation in Firestore
                            final consultationMap = Consultation(
                              id: consId,
                              medecinId: selectedMed.id,
                              patientNom: formattedNom,
                              patientPrenom: formattedPrenom,
                              statut: 'En attente',
                              encryptedKeyForHub: encryptedKeyForHub,
                              encryptedKeyForMedecin: encryptedKeyForMedecin,
                              encryptedPatientData: encryptedPatientData,
                              encryptedGarantieUrl: encryptedGarantieUrl,
                            ).toMap();

                            if (tLat != null) consultationMap['gpsTargetLat'] = tLat;
                            if (tLng != null) consultationMap['gpsTargetLng'] = tLng;

                            await docRef.set(consultationMap).timeout(const Duration(seconds: 15));

                            if (context.mounted) {
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Demande envoyée au médecin en toute sécurité !')));
                            }
                          } on TimeoutException {
                            if (context.mounted) {
                              setDialogState(() {
                                isUploading = false;
                              });
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Délai dépassé (Timeout). Vérifiez votre connexion internet.')),
                              );
                            }
                          } catch (e) {
                            if (context.mounted) {
                              setDialogState(() {
                                isUploading = false;
                              });
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur: $e')));
                            }
                          }
                        },
                  child: isUploading
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Envoyer (Chiffré)'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showReassignDialog(Consultation cons) async {
    List<Medecin> availableMedecins = [];
    try {
      final snap = await _firestore.collection('medecins').get();
      availableMedecins = snap.docs
          .map((doc) => Medecin.fromMap(doc.data(), doc.id))
          .where((m) => m.statut == 'Actif' || m.statut == 'Conventionné')
          .toList();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur récupération médecins: $e')));
      }
      return;
    }

    if (!mounted) return;

    if (availableMedecins.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Aucun médecin disponible pour réassignation.')));
      return;
    }

    String? selectedMedecinId = availableMedecins.first.id;

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Modifier / Réassigner le Médecin'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Demande actuelle : ${cons.id.substring(0, 8)}...', style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              const Text('Sélectionner le nouveau médecin :'),
              DropdownButtonFormField<String>(
                value: selectedMedecinId,
                items: availableMedecins.map((med) {
                  return DropdownMenuItem(value: med.id, child: Text('Dr. ${med.nom} - ${med.specialite}'));
                }).toList(),
                onChanged: (val) {
                  selectedMedecinId = val;
                },
                decoration: const InputDecoration(labelText: 'Nouveau Médecin'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
            ElevatedButton(
              onPressed: () async {
                final newMed = availableMedecins.firstWhere((m) => m.id == selectedMedecinId);
                var newMedPubKeyBase64 = newMed.publicKeyBase64;
                try {
                  final freshDoc = await _firestore.collection('medecins').doc(newMed.id).get();
                  if (freshDoc.exists && freshDoc.data() != null) {
                    final freshKey = freshDoc.data()!['publicKeyBase64'] as String?;
                    if (freshKey != null && freshKey.isNotEmpty) {
                      newMedPubKeyBase64 = freshKey;
                    }
                  }
                } catch (_) {}

                if (newMedPubKeyBase64 == null || newMedPubKeyBase64.isEmpty) {
                  final rsaPair = EncryptionEngine.generateRSAKeyPair();
                  final pubMap = {
                    'modulus': rsaPair.publicKey.modulus.toString(),
                    'exponent': rsaPair.publicKey.exponent.toString(),
                  };
                  newMedPubKeyBase64 = base64Encode(utf8.encode(jsonEncode(pubMap)));
                  await _firestore.collection('medecins').doc(newMed.id).update({
                    'publicKeyBase64': newMedPubKeyBase64,
                  });
                }

                try {
                  // Déchiffrer la clé AES avec la clé privée RSA du Hub
                  final hubPrivKey = await HubSecurityManager.getPrivateKey();
                  final aesKeyBase64 = EncryptionEngine.decryptRSA(cons.encryptedKeyForHub, hubPrivKey);

                  // Chiffrer la clé AES avec la clé publique RSA du nouveau médecin
                  final medPublicKey = EncryptionEngine.parsePublicKeyFromBase64(newMedPubKeyBase64);
                  final newEncryptedKeyForMedecin = EncryptionEngine.encryptRSA(aesKeyBase64, medPublicKey);

                  // Mettre à jour Firestore
                  await _firestore.collection('consultations').doc(cons.id).update({
                    'medecinId': newMed.id,
                    'statut': 'En attente',
                    'encryptedKeyForMedecin': newEncryptedKeyForMedecin,
                  });

                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Demande réassignée avec succès au Dr. ${newMed.nom} (${newMed.specialite})')));
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur lors de la réassignation : $e')));
                  }
                }
              },
              child: const Text('Réassigner (Chiffré)'),
            ),
          ],
        );
      },
    );
  }

  void _showDeleteDialog(Consultation cons) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Supprimer la demande ?'),
          content: Text('Voulez-vous vraiment supprimer définitivement la demande de consultation (${cons.id.substring(0, 8)}...) ? Cette action est irréversible.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
              onPressed: () async {
                try {
                  await _firestore.collection('consultations').doc(cons.id).delete();
                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Demande de consultation supprimée avec succès.')));
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur de suppression : $e')));
                  }
                }
              },
              child: const Text('Supprimer'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Demandes & Consultations', style: Theme.of(context).textTheme.headlineSmall),
              ElevatedButton.icon(
                onPressed: _showCreateConsultationDialog,
                icon: const Icon(Icons.add_task),
                label: const Text('Créer une Demande'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.green.shade200),
            ),
            child: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green.shade700, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Connexion établie — Synchronisation en direct avec ELAA DocPocket Med',
                    style: TextStyle(
                      color: Colors.green.shade900,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _firestore.collection('consultations').snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(child: Text('Aucune consultation en cours.'));
                }

                final docs = snapshot.data!.docs;

                return ListView.builder(
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final data = docs[index].data() as Map<String, dynamic>;
                    final cons = Consultation.fromMap(data, docs[index].id);

                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.monitor_heart, color: Colors.teal),
                                    const SizedBox(width: 8),
                                    Text(
                                      (cons.patientNom != null && cons.patientNom!.isNotEmpty)
                                          ? '${cons.patientPrenom ?? ""} ${cons.patientNom}'
                                          : 'Consultation ID: ${cons.id.substring(0, 8)}...',
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                    ),
                                  ],
                                ),
                                Chip(
                                  label: Text(cons.statut, style: const TextStyle(fontWeight: FontWeight.w600)),
                                  backgroundColor: cons.statut == 'Acceptée'
                                      ? Colors.green.shade100
                                      : (cons.statut == 'Refusée' ? Colors.red.shade100 : Colors.orange.shade100),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Text('Médecin Assigné : ', style: TextStyle(color: Colors.grey.shade700)),
                                DoctorNameBadge(medecinId: cons.medecinId),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Wrap(
                              alignment: WrapAlignment.end,
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                ElevatedButton.icon(
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => Scaffold(
                                          appBar: AppBar(title: const Text('Dossier de Consultation')),
                                          body: ActiveConsultationView(consultation: cons),
                                        ),
                                      ),
                                    );
                                  },
                                  icon: const Icon(Icons.description, size: 18),
                                  label: const Text('Voir Dossier / Rapport'),
                                ),
                                OutlinedButton.icon(
                                  onPressed: () => _showReassignDialog(cons),
                                  icon: const Icon(Icons.swap_horiz, size: 18, color: Colors.blue),
                                  label: const Text('Changer de médecin', style: TextStyle(color: Colors.blue)),
                                ),
                                OutlinedButton.icon(
                                  onPressed: () => _showDeleteDialog(cons),
                                  icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                                  label: const Text('Supprimer', style: TextStyle(color: Colors.red)),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

