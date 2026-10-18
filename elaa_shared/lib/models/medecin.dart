class Medecin {
  final String id;
  final String nom;
  final String prenom;
  final String specialite;
  final String numeroOrdre;
  final String ville;
  final String telephone;
  final String email;
  final DateTime dateDebutConvention;
  final String licenceKey;
  final String? publicKeyBase64;
  final String statut;
  final int? dureeValiditeJours; // null ou <= 0 = Illimité
  final int maxAppareils; // <= 0 = Illimité
  final int nombreAppareilsActifs;

  Medecin({
    required this.id,
    required this.nom,
    required this.prenom,
    required this.specialite,
    required this.numeroOrdre,
    required this.ville,
    required this.telephone,
    required this.email,
    required this.dateDebutConvention,
    required this.licenceKey,
    this.publicKeyBase64,
    this.statut = 'Actif',
    this.dureeValiditeJours,
    this.maxAppareils = 1,
    this.nombreAppareilsActifs = 0,
  });

  bool get isLicenceExpired {
    if (dureeValiditeJours == null || dureeValiditeJours! <= 0) {
      return false;
    }
    final expiryDate = dateDebutConvention.add(Duration(days: dureeValiditeJours!));
    return DateTime.now().isAfter(expiryDate);
  }

  String get validiteDescription {
    if (dureeValiditeJours == null || dureeValiditeJours! <= 0) {
      return 'Illimitée';
    }
    final expiryDate = dateDebutConvention.add(Duration(days: dureeValiditeJours!));
    final df = '${expiryDate.day.toString().padLeft(2, '0')}/${expiryDate.month.toString().padLeft(2, '0')}/${expiryDate.year}';
    return '$dureeValiditeJours jours (exp. le $df)';
  }

  String get appareilsDescription {
    final maxStr = (maxAppareils <= 0) ? 'Illimité' : '$maxAppareils';
    return '$nombreAppareilsActifs / $maxStr';
  }

  bool get isMaxAppareilsReached {
    if (maxAppareils <= 0) {
      return false; // Illimité
    }
    return nombreAppareilsActifs >= maxAppareils;
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'nom': nom,
      'prenom': prenom,
      'specialite': specialite,
      'numeroOrdre': numeroOrdre,
      'ville': ville,
      'telephone': telephone,
      'email': email,
      'dateDebutConvention': dateDebutConvention.toIso8601String(),
      'licenceKey': licenceKey,
      'publicKeyBase64': publicKeyBase64,
      'statut': statut,
      'dureeValiditeJours': dureeValiditeJours,
      'maxAppareils': maxAppareils,
      'nombreAppareilsActifs': nombreAppareilsActifs,
    };
  }

  factory Medecin.fromMap(Map<String, dynamic> map, String documentId) {
    return Medecin(
      id: documentId,
      nom: map['nom'] ?? '',
      prenom: map['prenom'] ?? '',
      specialite: map['specialite'] ?? '',
      numeroOrdre: map['numeroOrdre'] ?? '',
      ville: map['ville'] ?? '',
      telephone: map['telephone'] ?? '',
      email: map['email'] ?? '',
      dateDebutConvention: map['dateDebutConvention'] != null ? DateTime.parse(map['dateDebutConvention']) : DateTime.now(),
      licenceKey: map['licenceKey'] ?? '',
      publicKeyBase64: map['publicKeyBase64'],
      statut: map['statut'] ?? 'Actif',
      dureeValiditeJours: map['dureeValiditeJours'] as int?,
      maxAppareils: (map['maxAppareils'] as int?) ?? 1,
      nombreAppareilsActifs: (map['nombreAppareilsActifs'] as int?) ??
          ((map['publicKeyBase64'] != null && map['publicKeyBase64'].toString().isNotEmpty) ? 1 : 0),
    );
  }
}
