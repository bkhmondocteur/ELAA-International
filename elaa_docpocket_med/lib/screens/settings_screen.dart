import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String? _logoBase64;
  String? _ordonnanceBase64;
  String? _tamponBase64;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _logoBase64 = prefs.getString('settings_logo');
      _ordonnanceBase64 = prefs.getString('settings_ordonnance');
      _tamponBase64 = prefs.getString('settings_tampon');
    });
  }

  Future<void> _pickImage(String key) async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      final bytes = await File(pickedFile.path).readAsBytes();
      final base64String = base64Encode(bytes);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, base64String);
      setState(() {
        if (key == 'settings_logo') _logoBase64 = base64String;
        if (key == 'settings_ordonnance') _ordonnanceBase64 = base64String;
        if (key == 'settings_tampon') _tamponBase64 = base64String;
      });
    }
  }

  Widget _buildImageSetting({
    required String title,
    required String? base64Data,
    required String key,
  }) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 12),
            base64Data != null
                ? Image.memory(
                    base64Decode(base64Data),
                    height: 120,
                    fit: BoxFit.contain,
                  )
                : const Icon(Icons.image, size: 80, color: Colors.grey),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: () => _pickImage(key),
              icon: const Icon(Icons.upload),
              label: const Text('Uploader'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Réglages'),
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          _buildImageSetting(
            title: 'Logo du Cabinet',
            base64Data: _logoBase64,
            key: 'settings_logo',
          ),
          _buildImageSetting(
            title: 'Modèle de l\'Ordonnance (Entête)',
            base64Data: _ordonnanceBase64,
            key: 'settings_ordonnance',
          ),
          _buildImageSetting(
            title: 'Tampon et Signature',
            base64Data: _tamponBase64,
            key: 'settings_tampon',
          ),
        ],
      ),
    );
  }
}
