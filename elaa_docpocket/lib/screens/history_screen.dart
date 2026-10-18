import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:elaa_shared/elaa_shared.dart';
import 'active_consultation_view.dart';
import '../doctor_name_badge.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('consultations')
          .where('statut', isEqualTo: 'Clôturée')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(child: Text('Aucune consultation dans l\'historique.'));
        }

        final docs = snapshot.data!.docs;

        return ListView.builder(
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final cons = Consultation.fromMap(
              docs[index].data() as Map<String, dynamic>,
              docs[index].id,
            );

            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: ListTile(
                leading: const Icon(Icons.history, color: Colors.grey),
                title: Text((cons.patientNom != null && cons.patientNom!.isNotEmpty)
                    ? '${cons.patientPrenom ?? ""} ${cons.patientNom}'
                    : 'Consultation ID: ${cons.id}'),
                subtitle: Row(
                  children: [
                    const Text('Médecin : '),
                    DoctorNameBadge(medecinId: cons.medecinId),
                  ],
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => Scaffold(
                        appBar: AppBar(title: const Text('Détails Historique')),
                        body: ActiveConsultationView(consultation: cons, isHistory: true),
                      ),
                    ),
                  );
                },
              ),
            );
          },
        );
      },
    );
  }
}
