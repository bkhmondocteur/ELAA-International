import 'package:flutter/foundation.dart';
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
  final uri = Uri(scheme: 'mailto', path: to, queryParameters: {'subject': subject, 'body': body});
  await launchUrl(uri);
  return false;
}
