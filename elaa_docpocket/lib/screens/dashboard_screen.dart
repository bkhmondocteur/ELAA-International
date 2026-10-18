import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:elaa_shared/elaa_shared.dart';
import 'doctors_management_screen.dart';
import 'consultations_screen.dart';
import 'history_screen.dart';
import 'doctor_consultations_tab_screen.dart';
import 'keygen_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _selectedIndex = 0;

  final List<Widget> _basePages = [
    const ConsultationsScreen(),
    const DoctorsManagementScreen(),
    const HistoryScreen(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      LocalBackupService.checkAndPromptFolderSelection(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Image.asset('assets/icon.png', height: 36),
            const SizedBox(width: 12),
            const Text('ELAA DocPocket - Pro Hub'),
          ],
        ),
        actions: [
          Tooltip(
            message: 'Générer des clés de licence Médecin et Hub',
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purple.shade700,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              ),
              icon: const Icon(Icons.vpn_key, size: 20),
              label: const Text('Générer Licences', style: TextStyle(fontWeight: FontWeight.w600)),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const KeygenScreen()),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Tooltip(
            message: 'Changer l\'emplacement de sauvegarde automatique locale',
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue.shade700,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              ),
              icon: const Icon(Icons.settings, size: 20),
              label: const Text('Réglages Sauvegarde', style: TextStyle(fontWeight: FontWeight.w600)),
              onPressed: () => LocalBackupService.showFolderSelectionDialog(context, forced: true),
            ),
          ),
          const SizedBox(width: 16),
        ],
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('medecins').snapshots(),
        builder: (context, medSnapshot) {
          final Map<String, String> medNames = {};
          if (medSnapshot.hasData && medSnapshot.data != null) {
            for (var doc in medSnapshot.data!.docs) {
              final data = doc.data() as Map<String, dynamic>;
              final nom = data['nom'] ?? '';
              final prenom = data['prenom'] ?? '';
              medNames[doc.id] = (nom.isEmpty && prenom.isEmpty)
                  ? 'Médecin (${doc.id.substring(0, doc.id.length >= 4 ? 4 : doc.id.length)})'
                  : '$prenom $nom'.trim();
            }
          }

          return StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('consultations').snapshots(),
            builder: (context, snapshot) {
              final List<Consultation> activeCons = [];
              if (snapshot.hasData && snapshot.data != null) {
                for (var doc in snapshot.data!.docs) {
                  final cons = Consultation.fromMap(doc.data() as Map<String, dynamic>, doc.id);
                  if (cons.statut == 'En attente' ||
                      cons.statut == 'Acceptée' ||
                      cons.statut == 'En cours' ||
                      cons.statut == 'Terminée - RO') {
                    activeCons.add(cons);
                  }
                }
              }

              final List<NavigationRailDestination> destinations = [
                const NavigationRailDestination(
                  icon: Icon(Icons.monitor_heart_outlined),
                  selectedIcon: Icon(Icons.monitor_heart),
                  label: Text('Demandes'),
                ),
                const NavigationRailDestination(
                  icon: Icon(Icons.medical_services_outlined),
                  selectedIcon: Icon(Icons.medical_services),
                  label: Text('Médecins'),
                ),
                const NavigationRailDestination(
                  icon: Icon(Icons.history_outlined),
                  selectedIcon: Icon(Icons.history),
                  label: Text('Historique'),
                ),
              ];

              final List<Widget> pages = List.from(_basePages);

              // Group consultations by Doctor ID
              final Map<String, List<Consultation>> consByDoctor = {};
              for (var cons in activeCons) {
                consByDoctor.putIfAbsent(cons.medecinId, () => []).add(cons);
              }

              for (var entry in consByDoctor.entries) {
                final medId = entry.key;
                final consList = entry.value;
                final medName = medNames[medId] ?? 'Médecin ${medId.length >= 6 ? medId.substring(0, 6) : medId}';

                destinations.add(
                  NavigationRailDestination(
                    icon: const Icon(Icons.person_pin, color: Colors.blue),
                    selectedIcon: const Icon(Icons.person_pin, color: Colors.blue),
                    label: Text(
                      'Dr. $medName\n(${consList.length} demande${consList.length > 1 ? "s" : ""})',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ),
                );
                pages.add(DoctorConsultationsTabScreen(
                  medecinId: medId,
                  medecinNom: medName,
                  consultations: consList,
                ));
              }

              // Safety check in case a consultation was closed and the index goes out of bounds
              if (_selectedIndex >= pages.length) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) setState(() => _selectedIndex = 0);
                });
              }

              return Row(
                children: [
                  NavigationRail(
                    selectedIndex: _selectedIndex >= pages.length ? 0 : _selectedIndex,
                    onDestinationSelected: (int index) {
                      setState(() {
                        _selectedIndex = index;
                      });
                    },
                    labelType: NavigationRailLabelType.all,
                    destinations: destinations,
                  ),
                  const VerticalDivider(thickness: 1, width: 1),
                  Expanded(
                    child: pages[_selectedIndex >= pages.length ? 0 : _selectedIndex],
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

