import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:elaa_shared/elaa_shared.dart';

class DoctorNameBadge extends StatelessWidget {
  final String medecinId;
  final bool short;
  final TextStyle? style;

  const DoctorNameBadge({
    super.key,
    required this.medecinId,
    this.short = false,
    this.style,
  });

  static final Map<String, Medecin> _cache = {};

  @override
  Widget build(BuildContext context) {
    if (_cache.containsKey(medecinId)) {
      final med = _cache[medecinId]!;
      return Text(
        _formatName(med),
        style: style ?? TextStyle(color: Colors.grey.shade800, fontWeight: FontWeight.w600),
      );
    }

    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance.collection('medecins').doc(medecinId).get(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Text('Médecin : chargement...', style: style ?? TextStyle(color: Colors.grey.shade500));
        }
        if (!snapshot.hasData || !snapshot.data!.exists) {
          return Text('Médecin (ID: ${medecinId.length > 6 ? medecinId.substring(0, 6) : medecinId})',
              style: style ?? TextStyle(color: Colors.grey.shade700));
        }

        final data = snapshot.data!.data() as Map<String, dynamic>;
        final med = Medecin.fromMap(data, snapshot.data!.id);
        _cache[medecinId] = med;

        return Text(
          _formatName(med),
          style: style ?? TextStyle(color: Colors.grey.shade800, fontWeight: FontWeight.w600),
        );
      },
    );
  }

  String _formatName(Medecin med) {
    if (short) {
      return 'Dr. ${med.prenom} ${med.nom}';
    }
    return 'Dr. ${med.prenom} ${med.nom} (${med.specialite})';
  }
}
