import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';

/// ─────────────────────────────────────────────────────────────
///  ELAA Keygen Screen
///  Génère des clés de licence pour :
///    • Les médecins  → ELAAMED-V2-XXXX-XXXX-XXXX
///    • Le Hub        → ELAAHUB-V2-XXXX-XXXX-XXXX
/// ─────────────────────────────────────────────────────────────
class KeygenScreen extends StatefulWidget {
  const KeygenScreen({super.key});

  @override
  State<KeygenScreen> createState() => _KeygenScreenState();
}

class _KeygenScreenState extends State<KeygenScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Générateur de Licences'),
        backgroundColor: const Color(0xFF0284C7),
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          tabs: const [
            Tab(icon: Icon(Icons.medical_services), text: 'Licence Médecin'),
            Tab(icon: Icon(Icons.admin_panel_settings), text: 'Licence Hub'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: const [
          _MedecinKeygenTab(),
          _HubKeygenTab(),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
//  ONGLET 1 : Licence Médecin
// ═══════════════════════════════════════════════════════════════
class _MedecinKeygenTab extends StatefulWidget {
  const _MedecinKeygenTab();

  @override
  State<_MedecinKeygenTab> createState() => _MedecinKeygenTabState();
}

class _MedecinKeygenTabState extends State<_MedecinKeygenTab> {
  final _formKey = GlobalKey<FormState>();
  final _nomCtrl = TextEditingController();
  final _prenomCtrl = TextEditingController();
  final _ordreCtrl = TextEditingController();
  final _specialiteCtrl = TextEditingController();
  final _villeCtrl = TextEditingController();
  final _telCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();

  int _dureeJours = 365;
  int _maxAppareils = 2;
  bool _dureeIllimitee = false;

  String? _generatedKey;
  bool _isSaving = false;

  /// Génère une clé Médecin encodant le nom + n° ordre + aléatoire
  String _generateMedKey(String nom, String prenom, String ordre) {
    final rng = Random.secure();

    // Empreinte déterministe basée sur le médecin (4 hex chars)
    final raw = '${nom.toUpperCase()}${prenom.toUpperCase()}${ordre.toUpperCase()}';
    final fingerprint = sha256
        .convert(utf8.encode(raw))
        .toString()
        .substring(0, 4)
        .toUpperCase();

    // 3 segments aléatoires de 4 chars alphanumériques majuscules
    String seg() => List.generate(
          4,
          (_) => 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'[rng.nextInt(32)],
        ).join();

    return 'ELAAMED-V2-$fingerprint-${seg()}-${seg()}-${seg()}';
  }

  Future<void> _generateAndSave() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSaving = true;
      _generatedKey = null;
    });

    try {
      final nom = _nomCtrl.text.trim();
      final prenom = _prenomCtrl.text.trim();
      final ordre = _ordreCtrl.text.trim();
      final key = _generateMedKey(nom, prenom, ordre);

      // Sauvegarde dans Firestore collection 'medecins'
      await FirebaseFirestore.instance.collection('medecins').add({
        'nom': nom,
        'prenom': prenom,
        'specialite': _specialiteCtrl.text.trim(),
        'numeroOrdre': ordre,
        'ville': _villeCtrl.text.trim(),
        'telephone': _telCtrl.text.trim(),
        'email': _emailCtrl.text.trim(),
        'licenceKey': key,
        'statut': 'Actif',
        'dateDebutConvention': DateTime.now().toIso8601String(),
        'dureeValiditeJours': _dureeIllimitee ? 0 : _dureeJours,
        'maxAppareils': _maxAppareils,
        'nombreAppareilsActifs': 0,
        'publicKeyBase64': null,
      });

      setState(() => _generatedKey = key);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Info card ──────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFE0F2FE),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: Color(0xFF0284C7)),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'La clé générée sera automatiquement enregistrée dans Firebase. '
                      'Transmettez-la au médecin pour activer son application.',
                      style: TextStyle(fontSize: 13, color: Color(0xFF0369A1)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // ── Champs identité médecin ────────────────────────────────
            const _SectionTitle(icon: Icons.person, label: 'Identité du Médecin'),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: _Field(ctrl: _prenomCtrl, label: 'Prénom *', required: true)),
              const SizedBox(width: 12),
              Expanded(child: _Field(ctrl: _nomCtrl, label: 'Nom *', required: true)),
            ]),
            const SizedBox(height: 12),
            _Field(ctrl: _ordreCtrl, label: 'N° Ordre du Conseil Médical *', required: true),
            const SizedBox(height: 12),
            _Field(ctrl: _specialiteCtrl, label: 'Spécialité'),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: _Field(ctrl: _villeCtrl, label: 'Ville')),
              const SizedBox(width: 12),
              Expanded(child: _Field(ctrl: _telCtrl, label: 'Téléphone', phone: true)),
            ]),
            const SizedBox(height: 12),
            _Field(ctrl: _emailCtrl, label: 'Email', email: true),

            const SizedBox(height: 24),

            // ── Paramètres de licence ──────────────────────────────────
            const _SectionTitle(icon: Icons.settings, label: 'Paramètres de Licence'),
            const SizedBox(height: 12),

            // Durée
            SwitchListTile(
              title: const Text('Durée illimitée'),
              value: _dureeIllimitee,
              activeColor: const Color(0xFF0284C7),
              contentPadding: EdgeInsets.zero,
              onChanged: (v) => setState(() => _dureeIllimitee = v),
            ),
            if (!_dureeIllimitee) ...[
              Text('Durée de validité : $_dureeJours jours',
                  style: const TextStyle(fontWeight: FontWeight.w500)),
              Slider(
                value: _dureeJours.toDouble(),
                min: 30,
                max: 1825,
                divisions: 35,
                label: '$_dureeJours j',
                activeColor: const Color(0xFF0284C7),
                onChanged: (v) => setState(() => _dureeJours = v.round()),
              ),
            ],

            // Appareils max
            Text('Appareils autorisés : $_maxAppareils',
                style: const TextStyle(fontWeight: FontWeight.w500)),
            Slider(
              value: _maxAppareils.toDouble(),
              min: 1,
              max: 5,
              divisions: 4,
              label: '$_maxAppareils',
              activeColor: const Color(0xFF0284C7),
              onChanged: (v) => setState(() => _maxAppareils = v.round()),
            ),

            const SizedBox(height: 24),

            // ── Bouton génération ──────────────────────────────────────
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: _isSaving ? null : _generateAndSave,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0284C7),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                icon: _isSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.key),
                label: Text(
                    _isSaving ? 'Génération en cours...' : 'Générer la Licence Médecin'),
              ),
            ),

            // ── Résultat ───────────────────────────────────────────────
            if (_generatedKey != null) ...[
              const SizedBox(height: 24),
              _KeyResult(
                label: 'Licence Médecin générée',
                licenceKey: _generatedKey!,
                color: const Color(0xFF0284C7),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
//  ONGLET 2 : Licence Hub
// ═══════════════════════════════════════════════════════════════
class _HubKeygenTab extends StatefulWidget {
  const _HubKeygenTab();

  @override
  State<_HubKeygenTab> createState() => _HubKeygenTabState();
}

class _HubKeygenTabState extends State<_HubKeygenTab> {
  final _nomCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();

  String? _generatedKey;
  bool _isSaving = false;

  /// Génère une clé Hub avec empreinte + aléatoire
  String _generateHubKey(String nom) {
    final rng = Random.secure();
    final fingerprint = sha256
        .convert(utf8.encode(nom.toUpperCase()))
        .toString()
        .substring(0, 4)
        .toUpperCase();

    String seg() => List.generate(
          4,
          (_) => 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'[rng.nextInt(32)],
        ).join();

    return 'ELAAHUB-V2-$fingerprint-${seg()}-${seg()}-${seg()}';
  }

  Future<void> _generateAndSave() async {
    if (_nomCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Veuillez entrer un nom pour l\'opérateur.')),
      );
      return;
    }

    setState(() {
      _isSaving = true;
      _generatedKey = null;
    });

    try {
      final nom = _nomCtrl.text.trim();
      final key = _generateHubKey(nom);

      // Sauvegarde dans Firestore collection 'hub_licences'
      await FirebaseFirestore.instance.collection('hub_licences').add({
        'nom': nom,
        'email': _emailCtrl.text.trim(),
        'licenceKey': key,
        'statut': 'Actif',
        'dateCreation': DateTime.now().toIso8601String(),
      });

      setState(() => _generatedKey = key);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Info card ────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFEDE9FE),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(
              children: [
                Icon(Icons.shield, color: Color(0xFF7C3AED)),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'La clé Hub donne accès au tableau de bord Opérateur. '
                    'Transmettez-la à l\'opérateur ELAA concerné.',
                    style: TextStyle(fontSize: 13, color: Color(0xFF5B21B6)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          const _SectionTitle(
              icon: Icons.admin_panel_settings, label: 'Identité de l\'Opérateur'),
          const SizedBox(height: 12),
          _Field(ctrl: _nomCtrl, label: 'Nom complet de l\'opérateur *', required: true),
          const SizedBox(height: 12),
          _Field(ctrl: _emailCtrl, label: 'Email de l\'opérateur', email: true),
          const SizedBox(height: 24),

          // ── Bouton génération ────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              onPressed: _isSaving ? null : _generateAndSave,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF7C3AED),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              icon: _isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.vpn_key),
              label: Text(
                  _isSaving ? 'Génération en cours...' : 'Générer la Licence Hub'),
            ),
          ),

          // ── Résultat ─────────────────────────────────────────────────
          if (_generatedKey != null) ...[
            const SizedBox(height: 24),
            _KeyResult(
              label: 'Licence Hub générée',
              licenceKey: _generatedKey!,
              color: const Color(0xFF7C3AED),
            ),
          ],
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
//  Widgets réutilisables
// ═══════════════════════════════════════════════════════════════

class _SectionTitle extends StatelessWidget {
  final IconData icon;
  final String label;
  const _SectionTitle({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: const Color(0xFF0284C7)),
        const SizedBox(width: 8),
        Text(label,
            style: const TextStyle(
                fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF0369A1))),
      ],
    );
  }
}

class _Field extends StatelessWidget {
  final TextEditingController ctrl;
  final String label;
  final bool required;
  final bool phone;
  final bool email;

  const _Field({
    required this.ctrl,
    required this.label,
    this.required = false,
    this.phone = false,
    this.email = false,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: ctrl,
      keyboardType: phone
          ? TextInputType.phone
          : email
              ? TextInputType.emailAddress
              : TextInputType.text,
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
      validator: required
          ? (v) => (v == null || v.trim().isEmpty) ? 'Champ obligatoire' : null
          : null,
    );
  }
}

class _KeyResult extends StatelessWidget {
  final String label;
  final String licenceKey;
  final Color color;

  const _KeyResult(
      {required this.label, required this.licenceKey, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        border: Border.all(color: color.withOpacity(0.3)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.check_circle, color: color, size: 20),
            const SizedBox(width: 8),
            Text(label,
                style: TextStyle(
                    color: color, fontWeight: FontWeight.bold, fontSize: 14)),
          ]),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: SelectableText(
              licenceKey,
              style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2),
            ),
          ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: licenceKey));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Clé copiée dans le presse-papier !')),
                  );
                },
                icon: const Icon(Icons.copy, size: 16),
                label: const Text('Copier la clé'),
                style: OutlinedButton.styleFrom(
                    foregroundColor: color,
                    side: BorderSide(color: color.withOpacity(0.5))),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          Text(
            'Cette clé a été enregistrée automatiquement dans Firebase.',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
