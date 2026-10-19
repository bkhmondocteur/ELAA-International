import 'dart:convert';
import 'dart:io';
import 'web_helper.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

class LocalBackupService {
  static const String _folderKey = 'elaa_backup_folder';
  static const String _defaultMacFolder = '/Volumes/bkhmondocteur/Mes Applications/ELAA_Backups';
  static const String _defaultWebFolder = 'ELAA_Backups_Local';

  static Future<bool> isFolderConfigured() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey(_folderKey);
  }

  static Future<String> getBackupFolder() async {
    final prefs = await SharedPreferences.getInstance();
    final custom = prefs.getString(_folderKey);
    if (custom != null && custom.isNotEmpty) {
      return custom;
    }
    if (!kIsWeb) {
      if (Platform.isAndroid) {
        return '/storage/emulated/0/Documents/ELAA_Backups';
      } else if (Platform.isIOS) {
        return 'ELAA_Backups';
      } else {
        try {
          final testDir = Directory(_defaultMacFolder);
          if (testDir.existsSync() || _canCreateDir(_defaultMacFolder)) {
            return _defaultMacFolder;
          }
        } catch (_) {}
        final home = Platform.environment['HOME'] ?? '';
        if (home.isNotEmpty) {
          return '$home/Documents/ELAA_Backups';
        }
      }
    }
    return _defaultMacFolder;
  }

  static bool _canCreateDir(String path) {
    try {
      final d = Directory(path);
      if (!d.existsSync()) {
        d.createSync(recursive: true);
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> setBackupFolder(String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_folderKey, path);
  }

  static bool _promptedThisSession = false;

  static Future<void> checkAndPromptFolderSelection(BuildContext context, {bool forced = false}) async {
    final configured = await isFolderConfigured();
    if (!configured || forced) {
      if (!context.mounted) return;
      await showFolderSelectionDialog(context, forced: forced);
    } else if (!_promptedThisSession) {
      _promptedThisSession = true;
      if (!context.mounted) return;
      final folder = await getBackupFolder();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Emplacement de sauvegarde locale : $folder'),
          action: SnackBarAction(
            label: 'Modifier',
            textColor: Colors.amberAccent,
            onPressed: () => showFolderSelectionDialog(context, forced: true),
          ),
          duration: const Duration(seconds: 6),
        ),
      );
    }
  }

  static Future<void> showFolderSelectionDialog(BuildContext context, {bool forced = false}) async {
    final prefs = await SharedPreferences.getInstance();
    final currentPath = prefs.getString(_folderKey) ?? _defaultMacFolder;
    final controller = TextEditingController(text: currentPath);

    await showDialog(
      context: context,
      barrierDismissible: !forced,
      builder: (ctx) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.folder_special, color: Colors.blue),
              SizedBox(width: 8),
              Text('Dossier de Sauvegarde Automatique'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Veuillez choisir ou confirmer l\'emplacement de votre dossier de sauvegarde automatique locale et d\'archivage mensuel.',
                  style: TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 12),
                const Card(
                  color: Color(0xFFE8F5E9),
                  child: Padding(
                    padding: EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('🔒 Caractéristiques du moteur de sauvegarde :', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        SizedBox(height: 4),
                        Text('• Archivage organisé par mois (ex : 2026-07).', style: TextStyle(fontSize: 12)),
                        Text('• Rotation intelligente : conservation des 10 dernières sauvegardes.', style: TextStyle(fontSize: 12)),
                        Text('• Pièces jointes sauvegardées en un seul exemplaire local.', style: TextStyle(fontSize: 12)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: controller,
                  decoration: const InputDecoration(
                    labelText: 'Chemin du dossier de sauvegarde',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.folder),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            if (!forced)
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Annuler'),
              ),
            ElevatedButton.icon(
              onPressed: () async {
                final path = controller.text.trim();
                if (path.isNotEmpty) {
                  await setBackupFolder(path);
                  if (ctx.mounted) {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      SnackBar(content: Text('Dossier de sauvegarde configuré : $path')),
                    );
                  }
                }
              },
              icon: const Icon(Icons.check),
              label: const Text('Confirmer & Enregistrer'),
            ),
          ],
        );
      },
    );
  }

  static Future<String?> saveAutoBackup({
    required String consultationId,
    required String medecinId,
    required Map<String, dynamic> data,
    bool isManual = false,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final monthKey = '${now.year}-${now.month.toString().padLeft(2, '0')}';
    final backupFolder = await getBackupFolder();

    // Key for rotation list of this consultation
    final rotationKey = 'backup_rotation_$consultationId';
    final List<String> historyList = prefs.getStringList(rotationKey) ?? [];

    final backupEntry = {
      'consultationId': consultationId,
      'medecinId': medecinId,
      'timestamp': now.toIso8601String(),
      'monthArchive': monthKey,
      'folderPath': '$backupFolder/$medecinId/$monthKey',
      'data': data,
    };

    // Add new backup
    historyList.add(jsonEncode(backupEntry));

    // Maintain max 10 backups (11th overwrites oldest)
    while (historyList.length > 10) {
      historyList.removeAt(0);
    }

    await prefs.setStringList(rotationKey, historyList);
    await prefs.setString('latest_backup_$consultationId', jsonEncode(backupEntry));

    // 1) Écriture réelle sur le disque pour Mac / Windows / Android (!kIsWeb)
    if (!kIsWeb) {
      try {
        final dirPath = '$backupFolder/$medecinId/$monthKey';
        final dir = Directory(dirPath);
        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }

        final jsonFile = File('${dir.path}/consultation_${consultationId}.json');
        await jsonFile.writeAsString(jsonEncode(backupEntry), flush: true);

        final txtFile = File('${dir.path}/rapport_${consultationId}.txt');
        await txtFile.writeAsString(_generateReadableTxt(data, consultationId, medecinId), flush: true);

        final files = dir.listSync().whereType<File>().toList();
        if (files.length > 20) {
          files.sort((a, b) => a.lastModifiedSync().compareTo(b.lastModifiedSync()));
          while (files.length > 20) {
            try {
              files.first.deleteSync();
              files.removeAt(0);
            } catch (_) {}
          }
        }
        return dirPath;
      } catch (e) {
        debugPrint('Erreur écriture fichier disque : $e');
      }
    } else if (kIsWeb && isManual) {
      // 2) Sur le Web, si l'utilisateur clique sur "Sauvegarder", on déclenche le téléchargement
      try {
        final bytes = utf8.encode(jsonEncode(backupEntry));
        downloadWebFile(bytes, 'consultation_${consultationId}.json', 'application/json');

        final txtBytes = utf8.encode(_generateReadableTxt(data, consultationId, medecinId));
        downloadWebFile(txtBytes, 'rapport_${consultationId}.txt', 'text/plain');
        return 'Web Download';
      } catch (e) {
        debugPrint('Erreur téléchargement web : $e');
      }
    }
    return null;
  }

  static Future<String?> saveCustomFile(String fileName, List<int> bytes, {String? subDir}) async {
    if (kIsWeb) {
      try {
        downloadWebFile(bytes, fileName, 'application/octet-stream');
        return 'Web Download';
      } catch (_) {
        return null;
      }
    }
    try {
      final baseFolder = await getBackupFolder();
      final dirPath = subDir != null ? '$baseFolder/$subDir' : baseFolder;
      final dir = Directory(dirPath);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(bytes, flush: true);
      return file.path;
    } catch (e) {
      debugPrint('Erreur saveCustomFile: $e');
      return null;
    }
  }

  static String _generateReadableTxt(Map<String, dynamic> data, String consultationId, String medecinId) {
    final buffer = StringBuffer();
    buffer.writeln('====================================================');
    buffer.writeln('       ELAA INTERNATIONAL - DOSSIER MEDICAL         ');
    buffer.writeln('====================================================');
    buffer.writeln('ID Consultation : $consultationId');
    buffer.writeln('ID Médecin      : $medecinId');
    buffer.writeln('Date Sauvegarde : ${DateTime.now()}');
    buffer.writeln('----------------------------------------------------');

    if (data['patient'] != null) {
      final p = data['patient'] as Map<String, dynamic>;
      buffer.writeln('PATIENT:');
      buffer.writeln(' - Nom & Prénom : ${p['nom']} ${p['prenom']}');
      buffer.writeln(' - Téléphone    : ${p['tel']}');
      buffer.writeln(' - Assurance    : ${p['assurance']}');
      buffer.writeln('----------------------------------------------------');
    }

    if (data['rapport'] != null) {
      final r = data['rapport'] as Map<String, dynamic>;
      buffer.writeln('RAPPORT MEDICAL:');
      buffer.writeln(' - Diagnostic / Observations : ${r['diagnostic'] ?? ''}');
      buffer.writeln(' - Traitement recommandé     : ${r['traitement'] ?? ''}');
      buffer.writeln('----------------------------------------------------');
    }

    if (data['finance'] != null) {
      final f = data['finance'] as Map<String, dynamic>;
      buffer.writeln('RAPPORT FINANCIER:');
      buffer.writeln(' - Total HT   : ${f['totalHT']} TND');
      buffer.writeln(' - TVA        : ${f['tva']} TND');
      buffer.writeln(' - Total TTC  : ${f['totalTTC']} TND');
      buffer.writeln('----------------------------------------------------');
    }

    buffer.writeln('Fin de sauvegarde ELAA.');
    return buffer.toString();
  }

  static Future<List<Map<String, dynamic>>> getBackupHistory(String consultationId) async {
    final prefs = await SharedPreferences.getInstance();
    final rotationKey = 'backup_rotation_$consultationId';
    final List<String> historyList = prefs.getStringList(rotationKey) ?? [];
    return historyList.map((str) => jsonDecode(str) as Map<String, dynamic>).toList();
  }
  static Future<void> exportAllToCSV(BuildContext context, String? medecinId) async {
    try {
      final snapshot = await FirebaseFirestore.instance.collection('consultations').get();
      final docs = snapshot.docs;
      if (docs.isEmpty) {
        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Aucune donnée à exporter')));
        return;
      }

      final buffer = StringBuffer();
      buffer.writeln('ID,Date,Patient,Medecin,Statut');
      for (var doc in docs) {
        final data = doc.data();
        if (medecinId != null && data['medecinId'] != medecinId) continue;
        final patientNameRaw = '${data['patientNom'] ?? ''} ${data['patientPrenom'] ?? ''}'.trim();
        final patientName = patientNameRaw.isNotEmpty ? patientNameRaw : 'Inconnu';
        final medId = data['medecinId'] ?? 'N/A';
        final statut = data['statut'] ?? 'Inconnu';
        buffer.writeln('${doc.id},${DateTime.now().toIso8601String()},$patientName,$medId,$statut');
      }

      final bytes = utf8.encode(buffer.toString());
      final dateStr = DateTime.now().toIso8601String().substring(0, 10);
      await saveCustomFile('export_consultations_$dateStr.csv', bytes);

      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Exportation terminée')));
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur export: $e')));
    }
  }

  // --- BRIDGE SYNCHRONIZATION METHODS (FIRESTORE CHUNKING) ---

  static final Map<String, Uint8List> _webBridgeCache = {};
  static const int _chunkSizeBytes = 300 * 1024; // Morceaux de 300 Ko

  static String _getMimeType(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.gif')) return 'image/gif';
    return 'image/jpeg';
  }

  static Future<String?> checkLocalFile(String consultationId, String fileName) async {
    if (!kIsWeb) {
      try {
        final baseFolder = await getBackupFolder();
        final dirPath = '$baseFolder/Consultations/$consultationId';
        final file = File('$dirPath/$fileName');
        if (await file.exists()) {
          return file.path;
        }
      } catch (_) {}
    } else {
      final key = '${consultationId}_$fileName';
      if (_webBridgeCache.containsKey(key)) {
        final bytes = _webBridgeCache[key]!;
        final mime = _getMimeType(fileName);
        return 'data:$mime;base64,${base64Encode(bytes)}';
      }
      try {
        final prefs = await SharedPreferences.getInstance();
        final b64 = prefs.getString('local_bridge_$key');
        if (b64 != null && b64.isNotEmpty) {
          final mime = _getMimeType(fileName);
          return 'data:$mime;base64,$b64';
        }
      } catch (_) {}
    }
    return null;
  }

  static Future<String?> uploadToBridge(String consultationId, String fileName, Uint8List bytes) async {
    try {
      // 1. Sauvegarde locale d'abord
      if (!kIsWeb) {
        final baseFolder = await getBackupFolder();
        final dirPath = '$baseFolder/Consultations/$consultationId';
        final dir = Directory(dirPath);
        if (!await dir.exists()) await dir.create(recursive: true);
        final file = File('${dir.path}/$fileName');
        await file.writeAsBytes(bytes, flush: true);
      } else {
        final key = '${consultationId}_$fileName';
        _webBridgeCache[key] = bytes;
        try {
          final prefs = await SharedPreferences.getInstance();
          if (bytes.length < 2 * 1024 * 1024) {
            await prefs.setString('local_bridge_$key', base64Encode(bytes));
          }
        } catch (_) {}
      }
      
      // 2. Découpage du fichier en morceaux (chunks de 300 Ko) pour Firestore
      final int totalBytes = bytes.length;
      final int totalChunks = totalBytes == 0 ? 1 : (totalBytes / _chunkSizeBytes).ceil();

      // Nettoyer les anciens morceaux s'il y en avait
      try {
        final oldChunks = await FirebaseFirestore.instance
            .collection('consultations')
            .doc(consultationId)
            .collection('bridge_chunks')
            .where('fileName', isEqualTo: fileName)
            .get();
        for (var doc in oldChunks.docs) {
          await doc.reference.delete();
        }
      } catch (_) {}

      // Envoi de chaque morceau dans Firestore
      for (int i = 0; i < totalChunks; i++) {
        final start = i * _chunkSizeBytes;
        final end = (start + _chunkSizeBytes < totalBytes) ? start + _chunkSizeBytes : totalBytes;
        final chunkBytes = totalBytes == 0 ? Uint8List(0) : bytes.sublist(start, end);
        final chunkData = base64Encode(chunkBytes);

        await FirebaseFirestore.instance
            .collection('consultations')
            .doc(consultationId)
            .collection('bridge_chunks')
            .doc('${fileName}_chunk_$i')
            .set({
              'fileName': fileName,
              'chunkIndex': i,
              'totalChunks': totalChunks,
              'chunkData': chunkData,
              'totalSize': totalBytes,
              'createdAt': FieldValue.serverTimestamp(),
            });
      }

      // Mettre à jour les métadonnées sur le document consultation
      await FirebaseFirestore.instance.collection('consultations').doc(consultationId).set({
        'bridge_$fileName': fileName,
        'bridge_${fileName}_status': 'ready',
        'bridge_${fileName}_totalChunks': totalChunks,
        'bridge_${fileName}_totalSize': totalBytes,
      }, SetOptions(merge: true));
      
      return fileName;
    } catch (e) {
      debugPrint('Erreur uploadToBridge: $e');
      return null;
    }
  }

  static Future<String?> downloadFromBridge(String consultationId, String fileName) async {
    try {
      // 1. Vérifier si déjà présent en local
      final existingLocal = await checkLocalFile(consultationId, fileName);
      if (existingLocal != null) {
        return existingLocal;
      }

      // 2. Téléchargement des morceaux depuis Firestore
      final snapshot = await FirebaseFirestore.instance
          .collection('consultations')
          .doc(consultationId)
          .collection('bridge_chunks')
          .where('fileName', isEqualTo: fileName)
          .get();

      if (snapshot.docs.isEmpty) {
        debugPrint('Aucun morceau trouvé pour $fileName (consultation $consultationId)');
        return null;
      }

      final docs = snapshot.docs.toList()
        ..sort((a, b) => ((a.data()['chunkIndex'] as int?) ?? 0)
            .compareTo((b.data()['chunkIndex'] as int?) ?? 0));

      final int totalChunks = (docs.first.data()['totalChunks'] as int?) ?? docs.length;
      if (docs.length < totalChunks) {
        debugPrint('Morceaux incomplets: ${docs.length}/$totalChunks');
        return null;
      }

      // 3. Réassemblage des morceaux (collage local)
      final builder = BytesBuilder(copy: false);
      for (final doc in docs) {
        final b64 = doc.data()['chunkData'] as String?;
        if (b64 != null && b64.isNotEmpty) {
          builder.add(base64Decode(b64));
        }
      }
      final fullBytes = builder.takeBytes();

      // 4. Enregistrement local
      String resultPath;
      if (!kIsWeb) {
        final baseFolder = await getBackupFolder();
        final dirPath = '$baseFolder/Consultations/$consultationId';
        final dir = Directory(dirPath);
        if (!await dir.exists()) await dir.create(recursive: true);
        final file = File('${dir.path}/$fileName');
        await file.writeAsBytes(fullBytes, flush: true);
        resultPath = file.path;
      } else {
        final key = '${consultationId}_$fileName';
        _webBridgeCache[key] = fullBytes;
        try {
          final prefs = await SharedPreferences.getInstance();
          if (fullBytes.length < 2 * 1024 * 1024) {
            await prefs.setString('local_bridge_$key', base64Encode(fullBytes));
          }
        } catch (_) {}
        final mime = _getMimeType(fileName);
        resultPath = 'data:$mime;base64,${base64Encode(fullBytes)}';
      }

      // 5. Suppression immédiate de tous les morceaux du cloud
      await deleteFromBridge(consultationId, fileName);

      return resultPath;
    } catch (e) {
      debugPrint('Erreur downloadFromBridge: $e');
      return null;
    }
  }

  static Future<void> deleteFromBridge(String consultationId, String fileName) async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('consultations')
          .doc(consultationId)
          .collection('bridge_chunks')
          .where('fileName', isEqualTo: fileName)
          .get();

      final batch = FirebaseFirestore.instance.batch();
      for (final doc in snapshot.docs) {
        batch.delete(doc.reference);
      }

      batch.set(
        FirebaseFirestore.instance.collection('consultations').doc(consultationId),
        {
          'bridge_$fileName': FieldValue.delete(),
          'bridge_${fileName}_status': FieldValue.delete(),
          'bridge_${fileName}_totalChunks': FieldValue.delete(),
          'bridge_${fileName}_totalSize': FieldValue.delete(),
        },
        SetOptions(merge: true),
      );

      await batch.commit();
      debugPrint('Tous les morceaux de $fileName ont été effacés du cloud avec succès.');
    } catch (e) {
      debugPrint('Erreur deleteFromBridge: $e');
    }
  }
}
