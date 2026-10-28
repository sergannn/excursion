import 'dart:html';
import 'dart:typed_data';

/// Веб-специфичные функции для скачивания PDF
void downloadPdfWeb(Uint8List pdfBytes, String filename) {
  final blob = Blob([pdfBytes], 'application/pdf');
  final url = Url.createObjectUrlFromBlob(blob);
  AnchorElement(href: url)
    ..setAttribute('download', filename)
    ..click();
  Url.revokeObjectUrl(url);
}
