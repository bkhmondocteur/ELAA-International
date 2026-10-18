import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:elaa_shared/elaa_shared.dart';
import 'consultation_history_view.dart';
import 'consultation_form_screen.dart';

class MedHistoryScreen extends StatelessWidget {
  final String medecinId;
  const MedHistoryScreen({super.key, required this.medecinId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mon Historique (Archivées)'),
        actions: [
          IconButton(
            icon: const Icon(Icons.download),
            tooltip: 'Sauvegarde / Exporter',
            onPressed: () async {
              await LocalBackupService.exportAllToCSV(context, null); // Will fallback to all consultations for this doctor if we modify exportAllToCSV or it handles it.
            },
          ),
          IconButton(
            icon: const Icon(Icons.upload),
            tooltip: 'Importer',
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Importation non supportée dans cette version')));
            },
          ),
          IconButton(
            icon: const Icon(Icons.bar_chart),
            tooltip: 'Bilan par période',
            onPressed: () {
              // Same logic as DocPocket Pro (maybe a DateRangePicker then filter).
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bilan par période: Sélectionnez les dates')));
            },
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('consultations')
            .where('medecinId', isEqualTo: medecinId)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return Center(child: Text('Erreur: ${snapshot.error}'));
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const Center(child: Text('Aucune consultation achevée ou archivée.'));

          final docs = snapshot.data!.docs.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final st = data['statut'] as String?;
            return st != 'En attente' && st != 'Acceptée' && st != 'En cours';
          }).toList();

          if (docs.isEmpty) return const Center(child: Text('Aucune consultation achevée ou archivée.'));

          return ListView.builder(
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final doc = docs[index];
              final cons = Consultation.fromMap(doc.data() as Map<String, dynamic>, doc.id);
              
              return Card(
                child: ListTile(
                  title: Text(
                    (cons.patientNom != null && cons.patientNom!.isNotEmpty)
                        ? '${cons.patientPrenom ?? ""} ${cons.patientNom}'
                        : 'Consultation du dossier',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text('Statut: ${cons.statut} • ID: ${cons.id.substring(0, 8)}...'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.remove_red_eye, color: Colors.blue),
                        tooltip: 'Résumé rapide',
                        onPressed: () {
                          Navigator.push(context, MaterialPageRoute(builder: (_) => ConsultationHistoryView(consultation: cons)));
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.edit, color: Colors.teal),
                        tooltip: 'Modifier la consultation (Dossier complet)',
                        onPressed: () {
                          Navigator.push(context, MaterialPageRoute(builder: (_) => ConsultationFormScreen(consultationId: cons.id)));
                        },
                      ),
                    ],
                  ),
                  onTap: () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => ConsultationFormScreen(consultationId: cons.id)));
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}
