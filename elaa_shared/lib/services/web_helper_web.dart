// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:html' as html;

void downloadWebFile(List<int> bytes, String filename, String mimeType) {
  try {
    final blob = html.Blob([bytes], mimeType);
    final url = html.Url.createObjectUrlFromBlob(blob);
    html.AnchorElement(href: url)
      ..setAttribute('download', filename)
      ..click();
    html.Url.revokeObjectUrl(url);
  } catch (_) {}
}

void tryGetWebGeolocation(void Function(double lat, double lng) onSuccess) {
  try {
    html.window.navigator.geolocation.getCurrentPosition().then((pos) {
      final coords = pos.coords;
      if (coords != null && coords.latitude != null && coords.longitude != null) {
        onSuccess(coords.latitude!.toDouble(), coords.longitude!.toDouble());
      }
    }).catchError((_) {});
  } catch (_) {}
}
