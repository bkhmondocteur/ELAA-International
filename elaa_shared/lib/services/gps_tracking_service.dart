import 'dart:async';
import 'web_helper.dart';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';

class GpsTrackingService {
  static Timer? _timer;
  static bool _isTracking = false;
  static String? _activeConsultationId;

  // Tunis default coords (fallback)
  static double _currentLat = 36.8065;
  static double _currentLng = 10.1815;
  static double _startLat = 36.8065;
  static double _startLng = 10.1815;
  
  // Dynamically set when tracking starts
  static double _targetLat = 0.0;
  static double _targetLng = 0.0;

  static bool get isTracking => _isTracking;
  static String? get activeConsultationId => _activeConsultationId;
  static double get currentLat => _currentLat;
  static double get currentLng => _currentLng;

  static Future<void> _updateRealLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        tryGetWebGeolocation((lat, lng) {
          _currentLat = lat;
          _currentLng = lng;
        });
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          tryGetWebGeolocation((lat, lng) {
            _currentLat = lat;
            _currentLng = lng;
          });
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        tryGetWebGeolocation((lat, lng) {
          _currentLat = lat;
          _currentLng = lng;
        });
        return;
      }

      Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      _currentLat = position.latitude;
      _currentLng = position.longitude;
    } catch (e) {
      tryGetWebGeolocation((lat, lng) {
        _currentLat = lat;
        _currentLng = lng;
      });
    }
  }

  static Future<void> startTracking({
    required BuildContext context,
    required String consultationId,
    required double targetLat,
    required double targetLng,
    bool simulationMode = false,
  }) async {
    _isTracking = true;
    _activeConsultationId = consultationId;
    _targetLat = targetLat;
    _targetLng = targetLng;

    // Toujours tenter d'obtenir la position GPS réelle du médecin (ou HTML5 sur Web)
    await _updateRealLocation();
    _startLat = _currentLat;
    _startLng = _currentLng;

    _sendLocationUpdate(consultationId);

    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 4), (timer) async {
      if (!_isTracking) {
        timer.cancel();
        return;
      }
      if (simulationMode) {
        // En mode simulation/démo, on avance progressivement vers la destination à partir de la vraie position initiale
        _currentLat += (_targetLat - _currentLat) * 0.08 + (math.Random().nextDouble() - 0.5) * 0.0005;
        _currentLng += (_targetLng - _currentLng) * 0.08 + (math.Random().nextDouble() - 0.5) * 0.0005;
      } else {
        await _updateRealLocation();
      }
      _sendLocationUpdate(consultationId);
    });

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🛰️ Géolocalisation en direct activée : Partage de position GPS exacte en temps réel.'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  static Future<void> _sendLocationUpdate(String consultationId) async {
    try {
      await FirebaseFirestore.instance.collection('consultations').doc(consultationId).update({
        'gpsActive': true,
        'gpsLat': _currentLat,
        'gpsLng': _currentLng,
        'gpsStartLat': _startLat,
        'gpsStartLng': _startLng,
        'gpsTargetLat': _targetLat,
        'gpsTargetLng': _targetLng,
        'gpsSpeedKmH': 42.5,
        'gpsStatus': 'En chemin vers l\'hôtel',
        'gpsUpdatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      // Ignore error if offline
    }
  }

  static void stopTracking(String consultationId) {
    _isTracking = false;
    _activeConsultationId = null;
    _timer?.cancel();
    _timer = null;
    try {
      FirebaseFirestore.instance.collection('consultations').doc(consultationId).update({
        'gpsActive': false,
        'gpsStatus': 'Arrivé / Sur place',
        'gpsUpdatedAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }
}
