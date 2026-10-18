import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:math' as math;
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:elaa_shared/elaa_shared.dart';
import 'consultation_form_screen.dart';
import 'pin_login_screen.dart';
import 'history_screen.dart';
import 'settings_screen.dart';

class DoctorDashboardScreen extends StatefulWidget {
  const DoctorDashboardScreen({super.key});

  @override
  State<DoctorDashboardScreen> createState() => _DoctorDashboardScreenState();
}

class _DoctorDashboardScreenState extends State<DoctorDashboardScreen> {
  String? _medecinId;
  String _nom = '';
  String _prenom = '';
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadMedecinId();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      LocalBackupService.checkAndPromptFolderSelection(context);
    });
  }

  Future<void> _loadMedecinId() async {
    final prefs = await SharedPreferences.getInstance();
    String? medId = prefs.getString('medecin_id');
    String nom = prefs.getString('medecin_nom') ?? '';
    String prenom = prefs.getString('medecin_prenom') ?? '';

    if (medId != null && (nom.isEmpty || prenom.isEmpty)) {
      try {
        final doc = await FirebaseFirestore.instance.collection('medecins').doc(medId).get();
        if (doc.exists && doc.data() != null) {
          nom = doc.data()!['nom'] ?? '';
          prenom = doc.data()!['prenom'] ?? '';
          await prefs.setString('medecin_nom', nom);
          await prefs.setString('medecin_prenom', prenom);
        }
      } catch (e) {
        debugPrint('Erreur lors du chargement des informations médecin: $e');
      }
    }

    if (medId == null) {
      try {
        var query = await FirebaseFirestore.instance.collection('medecins').where('statut', isEqualTo: 'Actif').limit(1).get();
        if (query.docs.isEmpty) {
          query = await FirebaseFirestore.instance.collection('medecins').limit(1).get();
        }
        if (query.docs.isNotEmpty) {
          final doc = query.docs.first;
          medId = doc.id;
          nom = doc.data()['nom'] ?? '';
          prenom = doc.data()['prenom'] ?? '';
          await prefs.setString('medecin_id', medId);
          await prefs.setString('medecin_nom', nom);
          await prefs.setString('medecin_prenom', prenom);
        }
      } catch (e) {
        debugPrint('Erreur auto-recovery du médecin: $e');
      }
    }

    if (mounted) {
      setState(() {
        _medecinId = medId;
        _nom = nom;
        _prenom = prenom;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: const [
              Icon(Icons.check_circle, color: Colors.white),
              SizedBox(width: 8),
              Expanded(child: Text('Connexion établie - Synchronisation en direct avec le Hub Opérateur ELAA')),
            ],
          ),
          backgroundColor: Colors.green.shade700,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  Future<void> _toggleGlobalGps() async {
    if (_medecinId == null) return;
    final snapshot = await FirebaseFirestore.instance
        .collection('consultations')
        .where('medecinId', isEqualTo: _medecinId)
        .get();
    
    final activeDocs = snapshot.docs.where((d) {
      final st = d.data()['statut'] as String?;
      return st == 'Acceptée' || st == 'En cours' || st == 'En attente';
    }).toList();

    if (activeDocs.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Aucune consultation active pour activer la géolocalisation.')),
      );
      return;
    }

    final firstDoc = activeDocs.first;
    final isGpsOn = firstDoc.data()['gpsActive'] == true;
    if (isGpsOn) {
      GpsTrackingService.stopTracking(firstDoc.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('🛑 Suivi GPS désactivé.')),
      );
    } else {
      final targetLat = (firstDoc.data()['gpsTargetLat'] as num?)?.toDouble() ?? 36.8320;
      final targetLng = (firstDoc.data()['gpsTargetLng'] as num?)?.toDouble() ?? 10.2310;
      GpsTrackingService.startTracking(
        context: context,
        consultationId: firstDoc.id,
        targetLat: targetLat,
        targetLng: targetLng,
        simulationMode: false,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🛰️ Géolocalisation activée (En route vers l\'hôtel) ! L\'opérateur suit votre position en direct.'),
          backgroundColor: Colors.green,
        ),
      );
    }
    setState(() {});
  }

  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    var p = 0.017453292519943295;
    var c = math.cos;
    var a = 0.5 - c((lat2 - lat1) * p) / 2 + 
          c(lat1 * p) * c(lat2 * p) * 
          (1 - c((lon2 - lon1) * p)) / 2;
    return 12742 * math.asin(math.sqrt(a)); // 2 * R; R = 6371 km
  }

  Future<void> _showGpsDialog(String consultationId, Map<String, dynamic> data) async {
    final targetLat = data['gpsTargetLat'] as double?;
    final targetLng = data['gpsTargetLng'] as double?;

    if (targetLat != null && targetLng != null && mounted) {
      double dLat = GpsTrackingService.currentLat;
      double dLng = GpsTrackingService.currentLng;
      
      try {
        final position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
        ).timeout(const Duration(seconds: 3));
        dLat = position.latitude;
        dLng = position.longitude;
      } catch (_) {}

      final distanceKm = _calculateDistance(dLat, dLng, targetLat, targetLng);
      final estimatedTimeMinutes = (distanceKm / 40.0) * 60.0; // 40 km/h avg speed

      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Itinéraire estimé'),
            content: Text(
              'L\'hôtel se trouve à ${distanceKm.toStringAsFixed(1)} km.\n\n'
              'Temps estimé : ${estimatedTimeMinutes.toStringAsFixed(0)} minutes.\n\n'
              'Voulez-vous activer le GPS pour vous y rendre ?'
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Plus tard'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                onPressed: () {
                  Navigator.pop(ctx);
                  GpsTrackingService.startTracking(
                    context: context,
                    consultationId: consultationId,
                    targetLat: targetLat,
                    targetLng: targetLng,
                    simulationMode: false,
                  );
                  setState(() {});
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('🛰️ Géolocalisation active ! L\'opérateur suit votre trajet en direct.'),
                      backgroundColor: Colors.green,
                    ),
                  );
                },
                child: const Text('Activer le GPS'),
              ),
            ],
          ),
        );
      }
    } else {
      // Si on n'a pas les coordonnées de l'hôtel, on active simplement le GPS
      GpsTrackingService.startTracking(
        context: context,
        consultationId: consultationId,
        targetLat: targetLat ?? 36.8320, // fallback
        targetLng: targetLng ?? 10.2310, // fallback
        simulationMode: false,
      );
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🛰️ Géolocalisation active ! Coordonnées de l\'hôtel non disponibles.'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  Future<void> _acceptConsultation(String consultationId, Map<String, dynamic> data) async {
    await FirebaseFirestore.instance.collection('consultations').doc(consultationId).update({
      'statut': 'Acceptée',
    });

    await _showGpsDialog(consultationId, data);
  }

  Future<void> _rejectConsultation(String consultationId) async {
    await FirebaseFirestore.instance.collection('consultations').doc(consultationId).update({
      'statut': 'Refusée',
    });
  }

  Widget _buildConsultationsTab() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.teal.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.teal.shade200),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: Colors.teal.shade600,
                  child: const Icon(Icons.person_pin, color: Colors.white, size: 26),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        (_prenom.isNotEmpty || _nom.isNotEmpty)
                            ? 'Bonjour Docteur $_prenom $_nom'
                            : 'Bonjour Docteur',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 17,
                          color: Colors.teal.shade900,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(Icons.check_circle, color: Colors.green.shade700, size: 18),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Connexion établie • Synchronisation active avec le Hub',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.green.shade800,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text('Mes Consultations', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 12),
          if (_medecinId == null)
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  const Text('Recherche du profil médecin en cours...'),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: _loadMedecinId,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Actualiser'),
                  ),
                ],
              ),
            )
          else
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('consultations')
                    .where('medecinId', isEqualTo: _medecinId)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(
                      child: Text(
                        'Erreur de synchronisation : ${snapshot.error}',
                        style: const TextStyle(color: Colors.red),
                      ),
                    );
                  }
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                    return const Center(child: Text('Aucune consultation pour le moment.'));
                  }

                  final docs = snapshot.data!.docs.where((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    final st = data['statut'] as String?;
                    return st == 'En attente' || st == 'Acceptée' || st == 'En cours';
                  }).toList();

                  if (docs.isEmpty) {
                    return const Center(child: Text('Aucune consultation en attente ou en cours.'));
                  }

                  return ListView.builder(
                    itemCount: docs.length,
                    itemBuilder: (context, index) {
                      final data = docs[index].data() as Map<String, dynamic>;
                      final cons = Consultation.fromMap(data, docs[index].id);

                      final isWaiting = cons.statut == 'En attente';

                      return Card(
                        color: isWaiting ? Colors.orange.shade50 : null,
                        child: ListTile(
                          leading: Icon(Icons.medical_services, color: isWaiting ? Colors.orange : Colors.teal),
                          title: Text(
                            (cons.patientNom != null && cons.patientNom!.isNotEmpty)
                                ? '${cons.patientPrenom ?? ""} ${cons.patientNom}'
                                : (isWaiting ? 'Nouvelle Demande' : 'Consultation ${cons.statut}'),
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            (cons.patientNom != null && cons.patientNom!.isNotEmpty)
                                ? 'Statut : ${cons.statut} • ID: ${cons.id.substring(0, 8)}...'
                                : 'ID: ${cons.id.substring(0, 8)}...',
                          ),
                          trailing: isWaiting
                              ? Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.close, color: Colors.red),
                                      onPressed: () => _rejectConsultation(cons.id),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.check, color: Colors.green),
                                      onPressed: () => _acceptConsultation(cons.id, data),
                                    ),
                                  ],
                                )
                              : Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    ElevatedButton.icon(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: (data['gpsActive'] == true) ? Colors.green.shade700 : Colors.indigo.shade600,
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                      ),
                                      icon: Icon(
                                        (data['gpsActive'] == true) ? Icons.gps_fixed : Icons.satellite_alt,
                                        size: 16,
                                      ),
                                      label: Text(
                                        (data['gpsActive'] == true) ? 'GPS Actif' : 'Activer GPS (En route)',
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                                      ),
                                      onPressed: () {
                                        if (data['gpsActive'] == true) {
                                          GpsTrackingService.stopTracking(cons.id);
                                          setState(() {});
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(content: Text('🛑 Suivi GPS arrêté.')),
                                          );
                                        } else {
                                          _showGpsDialog(cons.id, data);
                                        }
                                      },
                                    ),
                                    const SizedBox(width: 8),
                                    const Icon(Icons.arrow_forward_ios),
                                  ],
                                ),
                          onTap: isWaiting ? null : () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (context) => ConsultationFormScreen(consultationId: cons.id)),
                            );
                          },
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

  Widget _buildCurrentTab() {
    switch (_selectedIndex) {
      case 0:
        return _buildConsultationsTab();
      case 1:
        return MedHistoryScreen(medecinId: _medecinId ?? '');
      case 2:
        return const Center(child: Text('Profil Médecin Actif'));
      default:
        return _buildConsultationsTab();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Image.asset('assets/icon.png', height: 40),
            const SizedBox(width: 8),
            const Flexible(
              child: Text(
                'ELAA DocPocket Med',
                overflow: TextOverflow.ellipsis,
                softWrap: false,
              ),
            ),
          ],
        ),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          Tooltip(
            message: 'Activer / désactiver la géolocalisation',
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigo.shade600,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              ),
              icon: const Icon(Icons.satellite_alt, size: 18),
              label: const Text('GPS', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              onPressed: _toggleGlobalGps,
            ),
          ),
          const SizedBox(width: 6),
          Tooltip(
            message: 'Emplacement sauvegarde locale',
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue.shade700,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              ),
              icon: const Icon(Icons.settings, size: 18),
              label: const Text('Sauvegarde', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              onPressed: () => LocalBackupService.showFolderSelectionDialog(context, forced: true),
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Réglages',
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (context) => const SettingsScreen()));
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.redAccent, size: 22),
            tooltip: 'Verrouiller / Se déconnecter',
            onPressed: () {
              if (_medecinId != null) {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PinLoginScreen(medecinId: _medecinId!),
                  ),
                );
              } else {
                FirebaseAuth.instance.signOut();
              }
            },
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: _buildCurrentTab(),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) => setState(() => _selectedIndex = index),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.list_alt), label: 'Demandes'),
          BottomNavigationBarItem(icon: Icon(Icons.history), label: 'Historique'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profil'),
        ],
      ),
    );
  }
}

