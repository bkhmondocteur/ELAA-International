class Consultation {
  final String id;
  final String medecinId;
  final String? patientNom;
  final String? patientPrenom;
  final String statut; // En attente, Acceptée, En cours, Clôturée, Refusée
  final DateTime? heurePrevue;
  
  // Ces clés sont l'AES chiffrée avec le RSA public respectif
  final String encryptedKeyForHub;
  final String encryptedKeyForMedecin;

  // Données partagées chiffrées avec la clé AES de consultation
  final String? encryptedPatientData; // JSON (nom, prenom, hotel, chambre, age...)
  final String? encryptedRapport;
  final String? encryptedOrdonnance;
  final String? encryptedEtatFinancier;
  final String? encryptedPassportUrl;
  final String? encryptedGarantieUrl;
  
  // Données STRICTEMENT privées chiffrées avec la clé publique/PIN du médecin
  final String? encryptedDossierMedicalPrive;

  Consultation({
    required this.id,
    required this.medecinId,
    this.patientNom,
    this.patientPrenom,
    required this.statut,
    this.heurePrevue,
    required this.encryptedKeyForHub,
    required this.encryptedKeyForMedecin,
    this.encryptedPatientData,
    this.encryptedRapport,
    this.encryptedOrdonnance,
    this.encryptedEtatFinancier,
    this.encryptedPassportUrl,
    this.encryptedGarantieUrl,
    this.encryptedDossierMedicalPrive,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'medecinId': medecinId,
      'patientNom': patientNom,
      'patientPrenom': patientPrenom,
      'statut': statut,
      'heurePrevue': heurePrevue?.toIso8601String(),
      'encryptedKeyForHub': encryptedKeyForHub,
      'encryptedKeyForMedecin': encryptedKeyForMedecin,
      'encryptedPatientData': encryptedPatientData,
      'encryptedRapport': encryptedRapport,
      'encryptedOrdonnance': encryptedOrdonnance,
      'encryptedEtatFinancier': encryptedEtatFinancier,
      'encryptedPassportUrl': encryptedPassportUrl,
      'encryptedGarantieUrl': encryptedGarantieUrl,
      'encryptedDossierMedicalPrive': encryptedDossierMedicalPrive,
    };
  }

  factory Consultation.fromMap(Map<String, dynamic> map, String documentId) {
    return Consultation(
      id: documentId,
      medecinId: map['medecinId'] ?? '',
      patientNom: map['patientNom'] as String?,
      patientPrenom: map['patientPrenom'] as String?,
      statut: map['statut'] ?? 'En attente',
      heurePrevue: map['heurePrevue'] != null ? DateTime.parse(map['heurePrevue']) : null,
      encryptedKeyForHub: map['encryptedKeyForHub'] ?? '',
      encryptedKeyForMedecin: map['encryptedKeyForMedecin'] ?? '',
      encryptedPatientData: map['encryptedPatientData'],
      encryptedRapport: map['encryptedRapport'],
      encryptedOrdonnance: map['encryptedOrdonnance'],
      encryptedEtatFinancier: map['encryptedEtatFinancier'],
      encryptedPassportUrl: map['encryptedPassportUrl'],
      encryptedGarantieUrl: map['encryptedGarantieUrl'],
      encryptedDossierMedicalPrive: map['encryptedDossierMedicalPrive'],
    );
  }
}
