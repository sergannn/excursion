import 'booking.dart';

class WalletInfo {
  const WalletInfo({
    required this.user,
    required this.balance,
    required this.transactions,
  });

  final WalletUser user;
  final double balance;
  final List<WalletTransactionItem> transactions;

  factory WalletInfo.fromJson(Map<String, dynamic> json) {
    return WalletInfo(
      user: WalletUser.fromJson(json['user'] as Map<String, dynamic>),
      balance: double.tryParse(json['balance'].toString()) ?? 0,
      transactions: (json['transactions'] as List<dynamic>? ?? const [])
          .map((item) =>
              WalletTransactionItem.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }
}

class WalletUser {
  const WalletUser({
    required this.id,
    required this.name,
    required this.email,
  });

  final int id;
  final String name;
  final String email;

  factory WalletUser.fromJson(Map<String, dynamic> json) {
    return WalletUser(
      id: (json['id'] as num?)?.toInt() ?? 0,
      name: json['name'] as String? ?? '',
      email: json['email'] as String? ?? '',
    );
  }
}

class WalletTransactionItem {
  const WalletTransactionItem({
    required this.id,
    required this.amount,
    required this.description,
    required this.booking,
    required this.createdAt,
  });

  final int id;
  final double amount;
  final String description;
  final BookingItem? booking;
  final DateTime createdAt;

  factory WalletTransactionItem.fromJson(Map<String, dynamic> json) {
    return WalletTransactionItem(
      id: (json['id'] as num?)?.toInt() ?? 0,
      amount: double.tryParse(json['amount'].toString()) ?? 0,
      description: json['description'] as String? ?? '',
      booking: json['booking'] == null
          ? null
          : BookingItem.fromJson(json['booking'] as Map<String, dynamic>),
      createdAt: json['created_at'] != null && json['created_at'] is String
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
    );
  }

  /// Очищает описание от фраз "Продажа места" и "на экскурсию"
  String get cleanedDescription {
    String cleaned = description;
    // Убираем "Продажа места " в начале
    cleaned = cleaned.replaceFirst(RegExp(r'^Продажа места\s+'), '');
    // Убираем " на экскурсию" и все что после (включая название экскурсии в кавычках)
    cleaned = cleaned.replaceAll(RegExp(r'\s+на экскурсию.*$'), '');
    return cleaned.trim();
  }
}

class SalesInfo {
  const SalesInfo({
    required this.user,
    required this.totalSales,
    required this.bookings,
  });

  final WalletUser user;
  final double totalSales;
  final List<BookingItem> bookings;

  factory SalesInfo.fromJson(Map<String, dynamic> json) {
    return SalesInfo(
      user: WalletUser.fromJson(json['user'] as Map<String, dynamic>),
      totalSales: double.tryParse(json['total_sales'].toString()) ?? 0,
      bookings: (json['bookings'] as List<dynamic>? ?? const [])
          .map((item) => BookingItem.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }
}
