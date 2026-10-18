import 'dart:typed_data';

class EmailAttachment {
  final String filename;
  final Uint8List bytes;
  final String? mimeType;

  EmailAttachment({
    required this.filename,
    required this.bytes,
    this.mimeType,
  });
}

Future<void> launchMail(String subject, String body) async {}

Future<bool> launchMailWithAttachments({
  String? to,
  required String subject,
  required String body,
  List<EmailAttachment> attachments = const [],
}) async => false;
