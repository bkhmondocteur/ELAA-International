import 'package:url_launcher/url_launcher.dart';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:ui' as ui;

// Import conditionnel : dart:html sur Web, stub vide sur Android/macOS natif
// ignore: avoid_web_libraries_in_flutter
import 'html_stub.dart' if (dart.library.html) 'dart:html' as html;

class LiveDoctorTrackingDialog extends StatefulWidget {
  final String consultationId;
  final String doctorName;
  final String patientName;

  const LiveDoctorTrackingDialog({
    super.key,
    required this.consultationId,
    required this.doctorName,
    required this.patientName,
  });

  @override
  State<LiveDoctorTrackingDialog> createState() => _LiveDoctorTrackingDialogState();
}

class _LiveDoctorTrackingDialogState extends State<LiveDoctorTrackingDialog>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  String? _mapViewId;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  // ── Construit et enregistre l'iframe OSM dans le registre Flutter Web ──────
  String _buildMapIframe({
    required double docLat,
    required double docLng,
    required double targetLat,
    required double targetLng,
    bool hasTarget = false,
  }) {
    final viewId = 'osm-map-${widget.consultationId}';

    // Centre de la carte = milieu entre médecin et hôtel (si disponible)
    final centerLat = hasTarget ? (docLat + targetLat) / 2 : docLat;
    final centerLng = hasTarget ? (docLng + targetLng) / 2 : docLng;
    final zoom = hasTarget ? 13 : 15;

    // URL de l'itinéraire OSRM (OpenStreetMap Routing Machine)
    final routeUrl = hasTarget
        ? 'https://router.project-osrm.org/route/v1/driving/$docLng,$docLat;$targetLng,$targetLat?overview=full&geometries=geojson'
        : '';

    final htmlContent = '''
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8"/>
<link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css"/>
<script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"></script>
<style>
  body { margin: 0; padding: 0; }
  #map { width: 100%; height: 100%; }
  html, body { height: 100%; }
</style>
</head>
<body>
<div id="map"></div>
<script>
  const map = L.map('map').setView([$centerLat, $centerLng], $zoom);
  L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
    attribution: '© OpenStreetMap contributors',
    maxZoom: 19
  }).addTo(map);

  // Marqueur Médecin (bleu avec icône voiture)
  const doctorIcon = L.divIcon({
    html: '<div style="background:#2563eb;border:3px solid white;border-radius:50%;width:36px;height:36px;display:flex;align-items:center;justify-content:center;font-size:18px;box-shadow:0 2px 8px rgba(0,0,0,0.4);">🚗</div>',
    iconSize: [36, 36],
    iconAnchor: [18, 18],
    popupAnchor: [0, -20],
    className: ''
  });
  L.marker([$docLat, $docLng], { icon: doctorIcon })
    .addTo(map)
    .bindPopup('<b>Médecin</b><br>Position en direct')
    .openPopup();

  ${hasTarget ? '''
  // Marqueur Hôtel / Patient (rouge avec icône hôtel)
  const hotelIcon = L.divIcon({
    html: '<div style="background:#dc2626;border:3px solid white;border-radius:50%;width:36px;height:36px;display:flex;align-items:center;justify-content:center;font-size:18px;box-shadow:0 2px 8px rgba(0,0,0,0.4);">🏨</div>',
    iconSize: [36, 36],
    iconAnchor: [18, 18],
    popupAnchor: [0, -20],
    className: ''
  });
  L.marker([$targetLat, $targetLng], { icon: hotelIcon })
    .addTo(map)
    .bindPopup('<b>Patient / Hôtel</b><br>Destination');

  // Tracé de l'itinéraire via OSRM
  fetch('$routeUrl')
    .then(r => r.json())
    .then(data => {
      if (data.routes && data.routes[0]) {
        const coords = data.routes[0].geometry.coordinates.map(c => [c[1], c[0]]);
        L.polyline(coords, { color: '#2563eb', weight: 5, opacity: 0.8 }).addTo(map);
        map.fitBounds(L.latLngBounds([[$docLat, $docLng], [$targetLat, $targetLng]]).pad(0.15));
      }
    })
    .catch(() => {
      // Fallback: ligne droite si OSRM indisponible
      L.polyline([[$docLat, $docLng], [$targetLat, $targetLng]], {
        color: '#2563eb', weight: 4, opacity: 0.6, dashArray: '10, 8'
      }).addTo(map);
    });
  ''' : ''}
</script>
</body>
</html>
''';

    if (kIsWeb) {
      // ignore: undefined_prefixed_name
      ui.platformViewRegistry.registerViewFactory(viewId, (int id) {
        final iframe = html.IFrameElement()
          ..srcdoc = htmlContent
          ..style.border = 'none'
          ..style.width = '100%'
          ..style.height = '100%'
          ..allowFullscreen = true;
        return iframe;
      });
    }

    return viewId;
  }

  double _calculateDistanceKm(double lat1, double lon1, double lat2, double lon2) {
    const double r = 6371.0;
    final double dLat = _degToRad(lat2 - lat1);
    final double dLon = _degToRad(lon2 - lon1);
    final double a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_degToRad(lat1)) *
            math.cos(_degToRad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final double c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return r * c;
  }

  double _degToRad(double deg) => deg * (math.pi / 180.0);

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Container(
        width: 860,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.12),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance
              .collection('consultations')
              .doc(widget.consultationId)
              .snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData || !snapshot.data!.exists) {
              return const SizedBox(
                height: 250,
                child: Center(child: CircularProgressIndicator()),
              );
            }

            final data = snapshot.data!.data() as Map<String, dynamic>? ?? {};
            final bool gpsActive = data['gpsActive'] == true;

            final double startLat = (data['gpsStartLat'] ?? 36.8065).toDouble();
            final double startLng = (data['gpsStartLng'] ?? 10.1815).toDouble();
            final double targetLat = (data['gpsTargetLat'] ?? 0.0).toDouble();
            final double targetLng = (data['gpsTargetLng'] ?? 0.0).toDouble();
            final double currentLat = (data['gpsLat'] ?? startLat).toDouble();
            final double currentLng = (data['gpsLng'] ?? startLng).toDouble();
            final String gpsStatus = data['gpsStatus'] ?? 'En chemin vers l\'hôtel';
            final double speedKmH = (data['gpsSpeedKmH'] ?? 42.0).toDouble();

            final bool hasTarget = targetLat != 0.0 && targetLng != 0.0;

            final double totalDist = hasTarget
                ? math.max(0.5, _calculateDistanceKm(startLat, startLng, targetLat, targetLng))
                : 1.0;
            final double remainingDist = hasTarget
                ? _calculateDistanceKm(currentLat, currentLng, targetLat, targetLng)
                : 0.0;
            final double progress =
                hasTarget ? (1.0 - (remainingDist / totalDist)).clamp(0.05, 0.95) : 0.5;

            final double safeSpeed = speedKmH > 0 ? speedKmH : 1.0;
            final int etaMinutes = hasTarget
                ? math.max(1, (remainingDist / safeSpeed * 60).round())
                : 0;
            final DateTime estimatedArrivalTime =
                DateTime.now().add(Duration(minutes: etaMinutes));
            final String etaFormatted =
                '${estimatedArrivalTime.hour.toString().padLeft(2, '0')}:${estimatedArrivalTime.minute.toString().padLeft(2, '0')}';

            // Construction de la carte
            final String mapViewId = _buildMapIframe(
              docLat: currentLat,
              docLng: currentLng,
              targetLat: targetLat,
              targetLng: targetLng,
              hasTarget: hasTarget,
            );

            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── En-tête ─────────────────────────────────────────────
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: gpsActive
                            ? Colors.green.withOpacity(0.15)
                            : Colors.orange.withOpacity(0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        gpsActive ? Icons.satellite_alt : Icons.location_off,
                        color: gpsActive ? Colors.green.shade700 : Colors.orange.shade700,
                        size: 32,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Suivi GPS en Direct — ${widget.doctorName}',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1E293B),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Patient : ${widget.patientName} • $gpsStatus',
                            style: TextStyle(
                              color: Colors.grey.shade700,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 28),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // ── Métriques ETA ────────────────────────────────────────
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: gpsActive
                          ? [const Color(0xFF0F172A), const Color(0xFF1E3A8A)]
                          : [Colors.grey.shade800, Colors.grey.shade700],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildMetricItem(
                        icon: Icons.timer,
                        label: 'TEMPS ESTIMÉ (ETA)',
                        value: hasTarget ? '$etaMinutes min' : '—',
                        subValue: hasTarget ? 'Arrivée vers $etaFormatted' : 'Destination non définie',
                        color: Colors.amberAccent,
                      ),
                      Container(height: 40, width: 1, color: Colors.white24),
                      _buildMetricItem(
                        icon: Icons.speed,
                        label: 'VITESSE',
                        value: '${speedKmH.toStringAsFixed(0)} km/h',
                        subValue: 'En transit actif',
                        color: Colors.greenAccent,
                      ),
                      Container(height: 40, width: 1, color: Colors.white24),
                      _buildMetricItem(
                        icon: Icons.map_outlined,
                        label: 'DISTANCE RESTANTE',
                        value: hasTarget ? '${remainingDist.toStringAsFixed(2)} km' : '—',
                        subValue: hasTarget ? 'Sur ${totalDist.toStringAsFixed(2)} km total' : '',
                        color: Colors.lightBlueAccent,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // ── CARTE OPENSTREETMAP TEMPS RÉEL ───────────────────────
                Container(
                  height: 340,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.08),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  clipBehavior: Clip.hardEdge,
                  child: kIsWeb
                      ? HtmlElementView(viewType: mapViewId)
                      : _buildFallbackMap(
                          currentLat: currentLat,
                          currentLng: currentLng,
                          targetLat: targetLat,
                          targetLng: targetLng,
                          hasTarget: hasTarget,
                          progress: progress,
                          gpsActive: gpsActive,
                        ),
                ),
                const SizedBox(height: 16),

                // ── Position + Boutons carte ─────────────────────────────
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '📍 Médecin : ${currentLat.toStringAsFixed(5)}, ${currentLng.toStringAsFixed(5)}',
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        if (hasTarget)
                          Text(
                            '🏨 Hôtel   : ${targetLat.toStringAsFixed(5)}, ${targetLng.toStringAsFixed(5)}',
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                      ],
                    ),
                    Row(
                      children: [
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF3B82F6),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          onPressed: () async {
                            final url = hasTarget
                                ? 'https://www.google.com/maps/dir/?api=1&origin=$currentLat,$currentLng&destination=$targetLat,$targetLng'
                                : 'https://www.google.com/maps/search/?api=1&query=$currentLat,$currentLng';
                            try {
                              final uri = Uri.parse(url);
                              if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
                                await launchUrl(uri, mode: LaunchMode.platformDefault);
                              }
                            } catch (e) {
                              debugPrint('Erreur Google Maps: $e');
                            }
                          },
                          icon: const Icon(Icons.directions, size: 16),
                          label: const Text('Google Maps', style: TextStyle(fontSize: 12)),
                        ),
                        const SizedBox(width: 10),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF10B981),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          onPressed: () async {
                            final url = hasTarget
                                ? 'https://www.openstreetmap.org/directions?engine=fossgis_osrm_car&route=$currentLat,$currentLng;$targetLat,$targetLng'
                                : 'https://www.openstreetmap.org/?mlat=$currentLat&mlon=$currentLng&zoom=15';
                            try {
                              final uri = Uri.parse(url);
                              if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
                                await launchUrl(uri, mode: LaunchMode.platformDefault);
                              }
                            } catch (e) {
                              debugPrint('Erreur OpenStreetMap: $e');
                            }
                          },
                          icon: const Icon(Icons.map, size: 16),
                          label: const Text('OpenStreetMap', style: TextStyle(fontSize: 12)),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  // ── Fallback non-web : route animée + coordonnées ─────────────────────────
  Widget _buildFallbackMap({
    required double currentLat,
    required double currentLng,
    required double targetLat,
    required double targetLng,
    required bool hasTarget,
    required double progress,
    required bool gpsActive,
  }) {
    return Container(
      color: const Color(0xFFF1F5F9),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Indicateur de position stylisé
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                const Icon(Icons.location_on, size: 48, color: Color(0xFF2563EB)),
                const SizedBox(height: 8),
                Text(
                  'Médecin : ${currentLat.toStringAsFixed(4)}, ${currentLng.toStringAsFixed(4)}',
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                ),
                if (hasTarget) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Hôtel : ${targetLat.toStringAsFixed(4)}, ${targetLng.toStringAsFixed(4)}',
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 13, color: Color(0xFFDC2626)),
                  ),
                ],
                const SizedBox(height: 20),
                _buildAnimatedRoad(progress, gpsActive),
                const SizedBox(height: 12),
                Text(
                  gpsActive
                      ? '🚗 En route (${(progress * 100).round()}% du trajet parcouru)'
                      : '⏳ En attente de mise à jour GPS…',
                  style: TextStyle(
                    color: gpsActive ? Colors.teal.shade800 : Colors.grey.shade600,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricItem({
    required IconData icon,
    required String label,
    required String value,
    required String subValue,
    required Color color,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(width: 5),
            Text(label, style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 0.8)),
          ],
        ),
        const SizedBox(height: 3),
        Text(value, style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.bold)),
        Text(subValue, style: const TextStyle(color: Colors.white60, fontSize: 10)),
      ],
    );
  }

  Widget _buildAnimatedRoad(double progress, bool gpsActive) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double width = constraints.maxWidth;
        final double usableWidth = width - 60;
        final double carLeft = usableWidth * progress;

        return Stack(
          alignment: Alignment.centerLeft,
          children: [
            Container(
              height: 44,
              width: width,
              decoration: BoxDecoration(
                color: const Color(0xFF334155),
                borderRadius: BorderRadius.circular(22),
              ),
            ),
            Positioned(
              left: 20,
              right: 20,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(18, (index) => Container(
                  width: 14, height: 3,
                  decoration: BoxDecoration(
                    color: Colors.amberAccent.withOpacity(0.7),
                    borderRadius: BorderRadius.circular(2),
                  ),
                )),
              ),
            ),
            Positioned(
              left: 8,
              child: Container(
                width: 28, height: 28,
                decoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle),
                child: const Icon(Icons.play_arrow, color: Colors.white, size: 18),
              ),
            ),
            Positioned(
              right: 8,
              child: Container(
                width: 28, height: 28,
                decoration: const BoxDecoration(color: Colors.blueAccent, shape: BoxShape.circle),
                child: const Icon(Icons.local_hospital, color: Colors.white, size: 16),
              ),
            ),
            AnimatedPositioned(
              duration: const Duration(milliseconds: 1500),
              curve: Curves.easeInOut,
              left: 15 + carLeft,
              child: AnimatedBuilder(
                animation: _animController,
                builder: (context, child) {
                  final double bounce = gpsActive ? math.sin(_animController.value * 2 * math.pi) * 1.5 : 0.0;
                  return Transform.translate(offset: Offset(0, bounce), child: child);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade400,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.directions_car_filled, color: Color(0xFF0F172A), size: 20),
                      const SizedBox(width: 4),
                      Text('${(progress * 100).round()}%',
                          style: const TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.bold, fontSize: 11)),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
