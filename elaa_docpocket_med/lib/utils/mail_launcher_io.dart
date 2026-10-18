import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'mail_launcher_stub.dart';
export 'mail_launcher_stub.dart' show EmailAttachment;

Future<void> launchMail(String subject, String body) async {
  final uri = Uri(scheme: 'mailto', queryParameters: {'subject': subject, 'body': body});
  await launchUrl(uri);
}

Future<bool> launchMailWithAttachments({
  String? to,
  required String subject,
  required String body,
  List<EmailAttachment> attachments = const [],
}) async {
  try {
    if (attachments.isNotEmpty) {
      final tempDir = await getTemporaryDirectory();
      List<XFile> xFiles = [];
      for (final a in attachments) {
        final safeName = a.filename.replaceAll(RegExp(r'[/\\?%*:|"<> ]'), '_');
        final file = File('${tempDir.path}/$safeName');
        await file.writeAsBytes(a.bytes);
        xFiles.add(XFile(file.path, mimeType: a.mimeType));
      }
      await Share.shareXFiles(
        xFiles,
        subject: subject,
        text: body,
      );
      return true;
    } else {
      final uri = Uri(scheme: 'mailto', path: to, queryParameters: {'subject': subject, 'body': body});
      await launchUrl(uri);
      return true;
    }
  } catch (e) {
    debugPrint('Erreur launchMailWithAttachments IO: $e');
    final uri = Uri(scheme: 'mailto', path: to, queryParameters: {'subject': subject, 'body': body});
    await launchUrl(uri);
    return false;
  }
}
