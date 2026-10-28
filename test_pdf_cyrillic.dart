import 'dart:io';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:flutter/services.dart' show rootBundle;
import 'package:booking_app/src/features/common/utils/ticket_generator.dart';
import 'package:booking_app/src/data/models/booking.dart';
import 'package:booking_app/src/data/models/excursion.dart';
import 'package:booking_app/src/data/models/stop.dart';

void main() async {
  print('🧪 Тест генерации PDF с русскими символами...');
  
  // Создаем тестовые данные
  final excursion = Excursion(
    id: 1,
    title: 'Экскурсия по Москве',
    description: 'Обзорная экскурсия',
    dateTime: DateTime.now().add(Duration(days: 7)),
    maxSeats: 50,
    isActive: true,
    prices: {},
    tariffs: {},
    busSeats: [],
    assignedStaff: [],
  );
  
  final stop = Stop(id: 1, name: 'Остановка у метро');
  
  final seats = [
    SeatPassengerInfo(
      seatNumber: 5,
      passengerType: PassengerType.adult,
      price: 1500.0,
    ),
    SeatPassengerInfo(
      seatNumber: 6,
      passengerType: PassengerType.child,
      price: 1000.0,
    ),
  ];
  
  // Генерируем PDF
  final pdf = pw.Document();
  final dateFormatter = DateFormat('dd.MM.yyyy HH:mm');
  final total = seats.fold<double>(0, (sum, seat) => sum + seat.price);
  final ticketNumber = 'T-1-${DateTime.now().millisecondsSinceEpoch}-1234';
  
  final baseTextStyle = await TicketGenerator.textStyle();
  final boldTextStyle = await TicketGenerator.textStyle(fontWeight: pw.FontWeight.bold);
  final titleTextStyle = await TicketGenerator.textStyle(fontSize: 24, fontWeight: pw.FontWeight.bold);
  final sectionTextStyle = await TicketGenerator.textStyle(fontSize: 16, fontWeight: pw.FontWeight.bold);
  
  pdf.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      build: (context) {
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('Электронный билет', style: titleTextStyle),
            pw.SizedBox(height: 8),
            pw.Text('Номер: $ticketNumber', style: baseTextStyle),
            pw.SizedBox(height: 24),
            pw.Text(excursion.title, style: boldTextStyle),
            pw.SizedBox(height: 8),
            pw.Text('Дата: ${dateFormatter.format(excursion.dateTime)}', style: baseTextStyle),
            pw.Text('Остановка: ${stop.name}', style: baseTextStyle),
            pw.SizedBox(height: 16),
            pw.Divider(),
            pw.SizedBox(height: 16),
            pw.Text('Покупатель', style: sectionTextStyle),
            pw.SizedBox(height: 8),
            pw.Text('Имя: Иван Иванов', style: baseTextStyle),
            pw.Text('Телефон: +7 999 123-45-67', style: baseTextStyle),
            pw.SizedBox(height: 16),
            pw.Text('Пассажиры', style: sectionTextStyle),
            pw.SizedBox(height: 8),
            ...seats.map((seat) => pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 8),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('Место №${seat.seatNumber} - ${seat.passengerType.label}', style: boldTextStyle),
                  pw.Text('Цена: ${seat.price.toStringAsFixed(2)} ₽', style: baseTextStyle),
                ],
              ),
            )),
            pw.SizedBox(height: 16),
            pw.Text('Итого: ${total.toStringAsFixed(2)} ₽', style: boldTextStyle),
          ],
        );
      },
    ),
  );
  
  final pdfBytes = await pdf.save();
  final file = File('test_cyrillic_${DateTime.now().millisecondsSinceEpoch}.pdf');
  await file.writeAsBytes(pdfBytes);
  
  print('✅ PDF создан: ${file.absolute.path}');
  print('   Размер: ${pdfBytes.length} байт');
  print('   Откройте файл и проверьте отображение русских символов');
}
