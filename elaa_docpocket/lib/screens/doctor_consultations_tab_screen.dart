import 'package:flutter/material.dart';
import 'package:elaa_shared/elaa_shared.dart';
import 'active_consultation_view.dart';

class DoctorConsultationsTabScreen extends StatefulWidget {
  final String medecinId;
  final String medecinNom;
  final List<Consultation> consultations;

  const DoctorConsultationsTabScreen({
    super.key,
    required this.medecinId,
    required this.medecinNom,
    required this.consultations,
  });

  @override
  State<DoctorConsultationsTabScreen> createState() => _DoctorConsultationsTabScreenState();
}

class _DoctorConsultationsTabScreenState extends State<DoctorConsultationsTabScreen> with TickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: widget.consultations.length, vsync: this);
  }

  @override
  void didUpdateWidget(covariant DoctorConsultationsTabScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.consultations.length != widget.consultations.length) {
      _tabController.dispose();
      _tabController = TabController(length: widget.consultations.length, vsync: this);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Color _getStatusColor(String statut) {
    switch (statut) {
      case 'En attente':
        return Colors.orange;
      case 'Acceptée':
      case 'En cours':
      case 'Terminée - RO':
      case 'Terminée':
      case 'Clôturée':
        return Colors.green;
      case 'Refusée':
      case 'Refusé':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.consultations.isEmpty) {
      return Center(
        child: Text('Aucune consultation active pour Dr. ${widget.medecinNom}'),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.person_pin_circle, color: Colors.blue),
            const SizedBox(width: 8),
            Text(
              'Dr. ${widget.medecinNom} - Demandes en cours (${widget.consultations.length})',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        backgroundColor: Colors.blue.shade50,
        elevation: 1,
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          labelColor: Colors.blue.shade900,
          unselectedLabelColor: Colors.grey.shade700,
          indicatorColor: Colors.blue.shade800,
          indicatorWeight: 3,
          tabs: widget.consultations.map((cons) {
            final patientName = (cons.patientNom != null && cons.patientNom!.isNotEmpty)
                ? '${cons.patientPrenom ?? ""} ${cons.patientNom}'
                : 'Patient ID ${cons.id.substring(0, 6)}';
            final statusColor = _getStatusColor(cons.statut);
            return Tab(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: statusColor.withOpacity(0.6), width: 1.5),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: statusColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '$patientName • ${cons.statut}',
                      style: TextStyle(fontWeight: FontWeight.w700, color: statusColor.withAlpha(220)),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: widget.consultations.map<Widget>((cons) {
          return ActiveConsultationView(
            consultation: cons,
          );
        }).toList(),
      ),
    );
  }
}
