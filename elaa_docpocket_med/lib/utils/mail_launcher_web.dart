import 'dart:convert';
import 'dart:typed_data';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'package:flutter/foundation.dart';
import 'mail_launcher_stub.dart';
export 'mail_launcher_stub.dart' show EmailAttachment;

Future<void> launchMail(String subject, String body) async {
  final url = 'mailto:?subject=${Uri.encodeComponent(subject)}&body=${Uri.encodeComponent(body)}';
  html.window.open(url, '_self');
}

Future<bool> launchMailWithAttachments({
  String? to,
  required String subject,
  required String body,
  List<EmailAttachment> attachments = const [],
}) async {
  // 1. Appel du backend Express /api/send-mail (Electron sur macOS)
  try {
    final payload = {
      'to': to ?? '',
      'subject': subject,
      'bodyText': body,
      'filesArray': attachments.map((a) => {
        'filename': a.filename,
        'data': base64Encode(a.bytes),
        'isBase64': true,
      }).toList(),
    };

    final request = await html.HttpRequest.request(
      '/api/send-mail',
      method: 'POST',
      sendData: jsonEncode(payload),
      requestHeaders: {'Content-Type': 'application/json'},
    );

    if (request.status == 200) {
      final res = jsonDecode(request.responseText ?? '{}');
      if (res['success'] == true) {
        debugPrint('Apple Mail lancé avec ${res['count']} pièces jointes !');
        return true;
      }
    }
  } catch (e) {
    debugPrint('Information /api/send-mail : $e');
  }

  // 2. Repli pour navigateur web classique hors Electron :
  // Télécharger chaque pièce jointe pour que l'utilisateur les ait à portée de main
  for (final a in attachments) {
    try {
      final blob = html.Blob([a.bytes], a.mimeType ?? 'application/octet-stream');
      final url = html.Url.createObjectUrlFromBlob(blob);
      final anchor = html.AnchorElement(href: url)
        ..setAttribute('download', a.filename)
        ..style.display = 'none';
      html.document.body?.children.add(anchor);
      anchor.click();
      anchor.remove();
      html.Url.revokeObjectUrl(url);
    } catch (e) {
      debugPrint('Erreur download web pièce jointe: $e');
    }
  }

  // 3. Ouvrir le client mail système
  final toStr = to != null && to.isNotEmpty ? to : '';
  final url = 'mailto:$toStr?subject=${Uri.encodeComponent(subject)}&body=${Uri.encodeComponent(body)}';
  html.window.open(url, '_self');
  return false;
}
