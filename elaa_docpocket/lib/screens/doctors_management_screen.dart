import 'package:flutter/material.dart';
import 'package:elaa_shared/elaa_shared.dart';
import 'package:uuid/uuid.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';

class DoctorsManagementScreen extends StatefulWidget {
  const DoctorsManagementScreen({super.key});

  @override
  State<DoctorsManagementScreen> createState() => _DoctorsManagementScreenState();
}

class _DoctorsManagementScreenState extends State<DoctorsManagementScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  void _showAddDoctorDialog() {
    final nomController = TextEditingController();
    final prenomController = TextEditingController();
    final numeroOrdreController = TextEditingController();
    final villeController = TextEditingController();
    final telController = TextEditingController();
    final emailController = TextEditingController();
    String selectedSpecialite = 'Généraliste';
    
    final specialites = [
      'Généraliste', 'Cardiologue', 'Pédiatre', 'Dermatologue',
      'Gynécologue', 'Ophtalmologue', 'Psychiatre', 'Orthopédiste'
    ];

    bool isIllimite = true;
    bool appareilsIllimites = false;
    final dureeController = TextEditingController(text: '365');
    final maxAppareilsController = TextEditingController(text: '1');

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('Ajouter un Médecin Conventionné'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: nomController, decoration: const InputDecoration(labelText: 'Nom')),
                TextField(controller: prenomController, decoration: const InputDecoration(labelText: 'Prénom')),
                DropdownButtonFormField<String>(
                  value: selectedSpecialite,
                  items: specialites.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                  onChanged: (val) => selectedSpecialite = val!,
                  decoration: const InputDecoration(labelText: 'Spécialité'),
                ),
                TextField(controller: numeroOrdreController, decoration: const InputDecoration(labelText: 'Numéro d\'Ordre')),
                TextField(controller: villeController, decoration: const InputDecoration(labelText: 'Ville d\'exercice')),
                TextField(controller: telController, decoration: const InputDecoration(labelText: 'Téléphone')),
                TextField(controller: emailController, decoration: const InputDecoration(labelText: 'Email')),
                const Divider(),
                const Text('Configuration de la Licence', style: TextStyle(fontWeight: FontWeight.bold)),
                CheckboxListTile(
                  title: const Text('Durée de validité : Illimitée'),
                  value: isIllimite,
                  onChanged: (val) => setDialogState(() => isIllimite = val ?? true),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                ),
                if (!isIllimite)
                  TextField(
                    controller: dureeController,
                    decoration: const InputDecoration(labelText: 'Durée de validité (en jours, ex: 30, 365)'),
                    keyboardType: TextInputType.number,
                  ),
                CheckboxListTile(
                  title: const Text('Nombre d\'appareils : Illimité'),
                  value: appareilsIllimites,
                  onChanged: (val) => setDialogState(() => appareilsIllimites = val ?? false),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                ),
                if (!appareilsIllimites)
                  TextField(
                    controller: maxAppareilsController,
                    decoration: const InputDecoration(labelText: 'Nombre d\'appareils autorisés (ex: 1, 2, 5)'),
                    keyboardType: TextInputType.number,
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
              ElevatedButton(
                onPressed: () async {
                  final randomString = const Uuid().v4().substring(0, 5).toUpperCase();
                  final cleanNom = nomController.text.replaceAll(' ', '').toUpperCase();
                  final licenceKey = 'ELAAMED-V2-$cleanNom-$randomString';

                  final duree = isIllimite ? null : int.tryParse(dureeController.text);
                  final maxApp = appareilsIllimites ? -1 : (int.tryParse(maxAppareilsController.text) ?? 1);

                  final docRef = _firestore.collection('medecins').doc();
                  final newMedecin = Medecin(
                    id: docRef.id,
                    nom: nomController.text,
                    prenom: prenomController.text,
                    specialite: selectedSpecialite,
                    numeroOrdre: numeroOrdreController.text,
                    ville: villeController.text,
                    telephone: telController.text,
                    email: emailController.text,
                    dateDebutConvention: DateTime.now(),
                    licenceKey: licenceKey,
                    dureeValiditeJours: duree,
                    maxAppareils: maxApp,
                    nombreAppareilsActifs: 0,
                  );
                  
                  await docRef.set(newMedecin.toMap());

                  if (context.mounted) {
                    Navigator.pop(context);
                    showDialog(
                      context: context,
                      builder: (c) => AlertDialog(
                        title: const Text('Licence Générée avec Succès'),
                        content: Text('Veuillez transmettre cette clé de licence au Dr. ${newMedecin.nom} :\n\n${newMedecin.licenceKey}'),
                        actions: [
                          TextButton(
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: newMedecin.licenceKey));
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Clé copiée !')));
                            }, 
                            child: const Text('Copier')
                          ),
                          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Fermer'))
                        ],
                      )
                    );
                  }
                },
              child: const Text('Valider & Générer Licence'),
            ),
          ],
        ),
        );
      },
    );
  }

  void _showEditLicenceDialog(Medecin med) {
    bool isIllimite = med.dureeValiditeJours == null || med.dureeValiditeJours! <= 0;
    bool appareilsIllimites = med.maxAppareils <= 0;
    final dureeController = TextEditingController(text: isIllimite ? '365' : med.dureeValiditeJours.toString());
    final maxAppareilsController = TextEditingController(text: appareilsIllimites ? '1' : med.maxAppareils.toString());

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Paramètres Licence - Dr. ${med.nom}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CheckboxListTile(
                  title: const Text('Durée de validité : Illimitée'),
                  value: isIllimite,
                  onChanged: (val) => setDialogState(() => isIllimite = val ?? true),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                ),
                if (!isIllimite)
                  TextField(
                    controller: dureeController,
                    decoration: const InputDecoration(labelText: 'Durée de validité (en jours, ex: 30, 365)'),
                    keyboardType: TextInputType.number,
                  ),
                CheckboxListTile(
                  title: const Text('Nombre d\'appareils : Illimité'),
                  value: appareilsIllimites,
                  onChanged: (val) => setDialogState(() => appareilsIllimites = val ?? false),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                ),
                if (!appareilsIllimites)
                  TextField(
                    controller: maxAppareilsController,
                    decoration: const InputDecoration(labelText: 'Nombre d\'appareils autorisés (ex: 1, 2, 5)'),
                    keyboardType: TextInputType.number,
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
            ElevatedButton(
              onPressed: () async {
                final duree = isIllimite ? null : int.tryParse(dureeController.text);
                final maxApp = appareilsIllimites ? -1 : (int.tryParse(maxAppareilsController.text) ?? 1);

                await _firestore.collection('medecins').doc(med.id).update({
                  'dureeValiditeJours': duree,
                  'maxAppareils': maxApp,
                });
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Paramètres de licence mis à jour !')),
                  );
                }
              },
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8.0,
            runSpacing: 8.0,
            children: [
              Text('Médecins Conventionnés', style: Theme.of(context).textTheme.headlineSmall),
              ElevatedButton.icon(
                onPressed: _showAddDoctorDialog,
                icon: const Icon(Icons.person_add),
                label: const Text('Ajouter un Médecin'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _firestore.collection('medecins').orderBy('nom').snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(child: Text('Aucun médecin enregistré.'));
                }

                final docs = snapshot.data!.docs;

                return ListView.builder(
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final data = docs[index].data() as Map<String, dynamic>;
                    final med = Medecin.fromMap(data, docs[index].id);

                    return Card(
                      child: ListTile(
                        leading: const CircleAvatar(child: Icon(Icons.person)),
                        title: Text('Dr. ${med.prenom} ${med.nom} - ${med.specialite}'),
                        subtitle: Text(
                          '${med.ville} | Tél: ${med.telephone}\n'
                          'Licence: ${med.licenceKey}\n'
                          'Validité : ${med.validiteDescription} | Appareils : ${med.appareilsDescription}'
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.copy, color: Colors.blue),
                              onPressed: () {
                                Clipboard.setData(ClipboardData(text: med.licenceKey));
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Licence copiée !')));
                              },
                              tooltip: 'Copier Licence',
                            ),
                            IconButton(
                              icon: const Icon(Icons.settings, color: Colors.orange),
                              onPressed: () => _showEditLicenceDialog(med),
                              tooltip: 'Paramètres Licence (Validité / Appareils)',
                            ),
                            Chip(
                              label: Text(med.statut),
                              backgroundColor: med.statut == 'Actif' ? Colors.green.shade100 : Colors.red.shade100,
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () async {
                                final confirm = await showDialog<bool>(
                                  context: context,
                                  builder: (c) => AlertDialog(
                                    title: const Text('Confirmer la suppression'),
                                    content: Text('Voulez-vous vraiment supprimer le Dr. ${med.nom} ?'),
                                    actions: [
                                      TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuler')),
                                      TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Supprimer', style: TextStyle(color: Colors.red))),
                                    ],
                                  )
                                );
                                if (confirm == true) {
                                  await _firestore.collection('medecins').doc(med.id).delete();
                                }
                              },
                            )
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
