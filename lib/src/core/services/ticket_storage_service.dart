import 'dart:io';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import '../../data/models/saved_ticket.dart';

class TicketStorageService {
  static const String _ticketsDirName = 'tickets';
  static const String _metadataFileName = 'tickets_metadata.json';

  static TicketStorageService? _instance;
  static TicketStorageService get instance {
    _instance ??= TicketStorageService._();
    return _instance!;
  }

  TicketStorageService._();

  /// Получает директорию для сохранения билетов
  Future<Directory> _getTicketsDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    final ticketsDir = Directory('${appDir.path}/$_ticketsDirName');
    if (!await ticketsDir.exists()) {
      await ticketsDir.create(recursive: true);
    }
    return ticketsDir;
  }

  /// Получает путь к файлу метаданных
  Future<File> _getMetadataFile() async {
    final appDir = await getApplicationDocumentsDirectory();
    return File('${appDir.path}/$_metadataFileName');
  }

  /// Сохраняет билет и его метаданные
  Future<void> saveTicket({
    required List<int> pdfBytes,
    required SavedTicket ticket,
  }) async {
    final ticketsDir = await _getTicketsDirectory();
    final file = File('${ticketsDir.path}/${ticket.fileName}');
    
    // Сохраняем PDF файл
    await file.writeAsBytes(pdfBytes);
    
    // Сохраняем метаданные
    await _addTicketMetadata(ticket);
  }

  /// Добавляет метаданные билета в список
  Future<void> _addTicketMetadata(SavedTicket ticket) async {
    final metadataFile = await _getMetadataFile();
    List<SavedTicket> tickets = await getAllTickets();
    
    // Проверяем, нет ли уже такого билета
    tickets.removeWhere((t) => t.bookingId == ticket.bookingId && t.fileName == ticket.fileName);
    
    // Добавляем новый билет в начало списка
    tickets.insert(0, ticket);
    
    // Сохраняем обновленный список
    final jsonList = tickets.map((t) => t.toJson()).toList();
    await metadataFile.writeAsString(jsonEncode(jsonList));
  }

  /// Получает все сохраненные билеты
  Future<List<SavedTicket>> getAllTickets() async {
    final metadataFile = await _getMetadataFile();
    
    if (!await metadataFile.exists()) {
      return [];
    }
    
    try {
      final content = await metadataFile.readAsString();
      final jsonList = jsonDecode(content) as List<dynamic>;
      return jsonList.map((json) => SavedTicket.fromJson(json as Map<String, dynamic>)).toList();
    } catch (e) {
      return [];
    }
  }

  /// Получает файл билета по имени файла
  Future<File?> getTicketFile(String fileName) async {
    final ticketsDir = await _getTicketsDirectory();
    final file = File('${ticketsDir.path}/$fileName');
    
    if (await file.exists()) {
      return file;
    }
    return null;
  }

  /// Удаляет билет и его метаданные
  Future<void> deleteTicket(SavedTicket ticket) async {
    // Удаляем файл
    final ticketsDir = await _getTicketsDirectory();
    final file = File('${ticketsDir.path}/${ticket.fileName}');
    if (await file.exists()) {
      await file.delete();
    }
    
    // Удаляем из метаданных
    final metadataFile = await _getMetadataFile();
    if (await metadataFile.exists()) {
      List<SavedTicket> tickets = await getAllTickets();
      tickets.removeWhere((t) => 
        t.bookingId == ticket.bookingId && 
        t.fileName == ticket.fileName
      );
      
      final jsonList = tickets.map((t) => t.toJson()).toList();
      await metadataFile.writeAsString(jsonEncode(jsonList));
    }
  }

  /// Очищает все сохраненные билеты
  Future<void> clearAllTickets() async {
    final ticketsDir = await _getTicketsDirectory();
    if (await ticketsDir.exists()) {
      await ticketsDir.delete(recursive: true);
    }
    
    final metadataFile = await _getMetadataFile();
    if (await metadataFile.exists()) {
      await metadataFile.delete();
    }
  }
}
