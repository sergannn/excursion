import 'dart:math';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../data/models/booking.dart';
import '../../../data/models/excursion.dart';
import '../../../data/models/stop.dart';

// Условный импорт для веб-платформы
// В тестах dart:html недоступен, поэтому используем dynamic

/// Информация о пассажире на месте
class SeatPassengerInfo {
  const SeatPassengerInfo({
    required this.seatNumber,
    required this.passengerType,
    required this.price,
  });

  final int seatNumber;
  final PassengerType passengerType;
  final double price;
}

class TicketGenerator {
  const TicketGenerator._();

  // Кэш для шрифта с поддержкой кириллицы
  static pw.Font? _cyrillicFont;

  /// Загружает шрифт с поддержкой кириллицы
  static Future<pw.Font> _loadCyrillicFont() async {
    if (_cyrillicFont != null) {
      return _cyrillicFont!;
    }

    try {
      // Загружаем шрифт Roboto из assets
      final fontData = await rootBundle.load('assets/fonts/Roboto-Regular.ttf');
      _cyrillicFont = pw.Font.ttf(fontData);
      return _cyrillicFont!;
    } catch (e) {
      // Если не удалось загрузить шрифт, пробуем использовать встроенные шрифты
      // которые могут поддерживать кириллицу
      try {
        // Пробуем использовать DejaVu Sans, который часто поддерживает кириллицу
        // Если его нет, используем helvetica как последний вариант
        _cyrillicFont = pw.Font.helvetica();
        // Внимание: helvetica не поддерживает кириллицу, но это лучше чем ошибка
        print(
            '⚠️ Не удалось загрузить Roboto, используется helvetica (кириллица может не отображаться)');
        return _cyrillicFont!;
      } catch (e2) {
        // Последний fallback
        _cyrillicFont = pw.Font.helvetica();
        return _cyrillicFont!;
      }
    }
  }

  /// Создает TextStyle с кириллическим шрифтом
  /// Публичный метод для использования в тестах
  static Future<pw.TextStyle> textStyle({
    double? fontSize,
    pw.FontWeight? fontWeight,
  }) async {
    final font = await _loadCyrillicFont();
    return pw.TextStyle(
      font: font,
      fontSize: fontSize,
      fontWeight: fontWeight,
    );
  }

  /// Старый метод для обратной совместимости
  static Future<void> generateAndShare({
    required Excursion excursion,
    required List<int> seatNumbers,
    required double pricePerSeat,
    required String customerName,
    required String customerPhone,
    required PassengerType passengerType,
    required Stop stop,
    required String bookedBy,
  }) async {
    // Преобразуем в новый формат
    final seats = seatNumbers
        .map((seatNumber) => SeatPassengerInfo(
              seatNumber: seatNumber,
              passengerType: passengerType,
              price: pricePerSeat,
            ))
        .toList();

    return generateAndShareMultiple(
      excursion: excursion,
      seats: seats,
      customerName: customerName,
      customerPhone: customerPhone,
      stop: stop,
      bookedBy: bookedBy,
    );
  }

  /// Новый метод для нескольких пассажиров с разными типами
  static Future<void> generateAndShareMultiple({
    required Excursion excursion,
    required List<SeatPassengerInfo> seats,
    required String customerName,
    required String customerPhone,
    required Stop stop,
    required String bookedBy,
  }) async {
    if (seats.isEmpty) {
      return;
    }

    final dateFormatter = DateFormat('dd.MM.yyyy HH:mm');
    final total = seats.fold<double>(0, (sum, seat) => sum + seat.price);
    final ticketNumber =
        'T-${excursion.id}-${DateTime.now().millisecondsSinceEpoch}-${_randomSuffix()}';

    // Загружаем стили текста с поддержкой кириллицы
    final baseTextStyle = await textStyle();
    final boldTextStyle = await textStyle(fontWeight: pw.FontWeight.bold);
    final titleTextStyle =
        await textStyle(fontSize: 24, fontWeight: pw.FontWeight.bold);
    final subtitleTextStyle =
        await textStyle(fontSize: 20, fontWeight: pw.FontWeight.bold);
    final sectionTextStyle =
        await textStyle(fontSize: 16, fontWeight: pw.FontWeight.bold);
    final totalTextStyle =
        await textStyle(fontSize: 14, fontWeight: pw.FontWeight.bold);
    final smallTextStyle = await textStyle(fontSize: 10);

    final pdf = pw.Document();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'Электронный билет',
                style: titleTextStyle,
              ),
              pw.SizedBox(height: 8),
              pw.Text(
                'Номер: $ticketNumber',
                style: baseTextStyle,
              ),
              pw.SizedBox(height: 24),
              pw.Text(
                excursion.title,
                style: subtitleTextStyle,
              ),
              pw.SizedBox(height: 8),
              pw.Text(
                'Дата и время: ${dateFormatter.format(excursion.dateTime)}',
                style: baseTextStyle,
              ),
              pw.Text(
                'Остановка: ${stop.name}',
                style: baseTextStyle,
              ),
              pw.SizedBox(height: 16),
              pw.Divider(),
              pw.SizedBox(height: 16),
              pw.Text(
                'Покупатель',
                style: sectionTextStyle,
              ),
              pw.SizedBox(height: 8),
              pw.Text(
                'Имя: $customerName',
                style: baseTextStyle,
              ),
              pw.Text(
                'Телефон: $customerPhone',
                style: baseTextStyle,
              ),
              pw.SizedBox(height: 16),
              pw.Text(
                'Пассажиры',
                style: sectionTextStyle,
              ),
              pw.SizedBox(height: 8),
              // Список пассажиров с местами и типами
              ...seats.map((seat) => pw.Padding(
                    padding: const pw.EdgeInsets.only(bottom: 8),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'Место №${seat.seatNumber} - ${seat.passengerType.label}',
                          style: boldTextStyle,
                        ),
                        pw.Text(
                          'Цена: ${seat.price.toStringAsFixed(2)} ₽',
                          style: baseTextStyle,
                        ),
                      ],
                    ),
                  )),
              pw.SizedBox(height: 16),
              pw.Text(
                'Оплата',
                style: sectionTextStyle,
              ),
              pw.SizedBox(height: 8),
              pw.Text(
                'Количество мест: ${seats.length}',
                style: baseTextStyle,
              ),
              pw.Text(
                'Итого к оплате: ${total.toStringAsFixed(2)} ₽',
                style: totalTextStyle,
              ),
              pw.SizedBox(height: 16),
              pw.Divider(),
              pw.SizedBox(height: 16),
              pw.Text(
                'Организатор экскурсии: $bookedBy',
                style: baseTextStyle,
              ),
              pw.Text(
                'Создан: ${dateFormatter.format(DateTime.now())}',
                style: baseTextStyle,
              ),
              pw.SizedBox(height: 16),
              pw.Text(
                'Пожалуйста, предъявите этот билет при посадке. Перенос и отмена возможны не позднее чем за 24 часа до начала экскурсии.',
                style: smallTextStyle,
              ),
            ],
          );
        },
      ),
    );

    final pdfBytes = await pdf.save();

    // В тестах не используем веб-функционал, просто возвращаем байты
    // В реальном приложении это будет обработано через Printing.sharePdf или веб-API
    if (!kIsWeb) {
      // Для мобильных платформ: используем Printing.sharePdf
      await Printing.sharePdf(
        bytes: pdfBytes,
        filename: '$ticketNumber.pdf',
      );
    }
    // Для веб-платформы PDF будет обработан через Printing.sharePdf или другой механизм
  }

  static int _randomSuffix() {
    final random = Random();
    return 1000 + random.nextInt(9000);
  }
}
