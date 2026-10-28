import 'dart:typed_data';

/// Заглушка для веб-функций на не-веб платформах
void downloadPdfWeb(Uint8List pdfBytes, String filename) {
  throw UnsupportedError('downloadPdfWeb доступен только на веб-платформе');
}

