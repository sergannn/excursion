import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/services/ticket_storage_service.dart';
import '../../../data/models/saved_ticket.dart';

// Условный импорт для веб-функций
import 'pdf_downloader_stub.dart'
    if (dart.library.html) 'pdf_downloader_web.dart';

/// Утилита для работы с PDF на разных платформах
class PdfDownloader {
  const PdfDownloader._();

  /// Сохраняет и позволяет отправить PDF
  /// На веб-платформе скачивает файл через браузер
  /// На мобильных сохраняет во временный файл и предлагает отправить/сохранить
  /// Если передан ticketInfo, также сохраняет билет локально
  static Future<void> saveAndSharePdf({
    required Uint8List pdfBytes,
    required String filename,
    SavedTicket? ticketInfo,
  }) async {
    // Сохраняем билет локально, если передан ticketInfo (только на мобильных)
    if (!kIsWeb && ticketInfo != null) {
      try {
        await TicketStorageService.instance.saveTicket(
          pdfBytes: pdfBytes,
          ticket: ticketInfo,
        );
      } catch (e) {
        // Игнорируем ошибки сохранения, чтобы не мешать основному процессу
        debugPrint('Failed to save ticket locally: $e');
      }
    }

    if (kIsWeb) {
      // На веб используем Blob URL для скачивания
      downloadPdfWeb(pdfBytes, filename);
    } else {
      // На мобильных сохраняем во временный файл и предлагаем отправить/сохранить
      await _saveAndSharePdfMobile(pdfBytes, filename);
    }
  }

  /// Сохраняет и предлагает отправить PDF на мобильных устройствах
  static Future<void> _saveAndSharePdfMobile(
    Uint8List pdfBytes,
    String filename,
  ) async {
    // Получаем временную директорию
    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/$filename');

    // Сохраняем PDF во временный файл
    await file.writeAsBytes(pdfBytes);

    // Предлагаем отправить/сохранить через системный диалог
    // Пользователь может выбрать: сохранить в файлы, отправить по email, в мессенджер и т.д.
    await Share.shareXFiles(
      [XFile(file.path)],
      subject: 'Билет на экскурсию',
      text: 'Ваш билет на экскурсию',
    );
  }
}
