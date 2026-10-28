import 'booking.dart';
import 'wallet.dart';

class ProfitInfo {
  const ProfitInfo({
    required this.user,
    required this.totalProfit,
    required this.breakdown,
    required this.totalsByType,
    required this.isPartner,
  });

  final WalletUser user;
  final double totalProfit;
  final List<ProfitItem> breakdown;
  final Map<PassengerType, ProfitTotals> totalsByType;
  final bool isPartner;

  factory ProfitInfo.fromJson(Map<String, dynamic> json) {
    final userJson = json['user'];
    final userMap =
        userJson is Map<String, dynamic> ? userJson : const <String, dynamic>{};
    final totalsByTypeJson = json['totals_by_type'];
    final totalsByTypeMap = totalsByTypeJson is Map<String, dynamic>
        ? totalsByTypeJson
        : const <String, dynamic>{};

    return ProfitInfo(
      user: WalletUser.fromJson(userMap),
      totalProfit: double.tryParse(json['total_profit'].toString()) ?? 0,
      breakdown: (json['breakdown'] as List<dynamic>? ?? const [])
          .map((item) => ProfitItem.fromJson(item as Map<String, dynamic>))
          .toList(),
      totalsByType: _parseTotalsByType(totalsByTypeMap),
      isPartner: (json['is_partner'] as bool?) ??
          (userMap['is_partner'] as bool? ?? false),
    );
  }

  static Map<PassengerType, ProfitTotals> _parseTotalsByType(
    Map<String, dynamic> json,
  ) {
    final result = <PassengerType, ProfitTotals>{};
    for (final entry in json.entries) {
      final passengerType = PassengerTypeX.fromJson(entry.key);
      final value = entry.value;
      if (value is Map<String, dynamic>) {
        result[passengerType] = ProfitTotals(
          sales: double.tryParse(value['sales']?.toString() ?? '') ?? 0,
          commission:
              double.tryParse(value['commission']?.toString() ?? '') ?? 0,
        );
      }
    }
    return result;
  }
}

class ProfitItem {
  const ProfitItem({
    required this.bookingId,
    required this.excursion,
    required this.passengerType,
    required this.price,
    required this.commissionPercent,
    required this.commissionAmount,
    required this.bookedAt,
  });

  final int bookingId;
  final ProfitExcursion excursion;
  final PassengerType passengerType;
  final double price;
  final double commissionPercent;
  final double commissionAmount;
  final DateTime bookedAt;

  factory ProfitItem.fromJson(Map<String, dynamic> json) {
    return ProfitItem(
      bookingId: (json['booking_id'] as num?)?.toInt() ?? 0,
      excursion: ProfitExcursion.fromJson(
        json['excursion'] as Map<String, dynamic>,
      ),
      passengerType: PassengerTypeX.fromJson(
        json['passenger_type'] as String? ?? '',
      ),
      price: double.tryParse(json['price']?.toString() ?? '') ?? 0,
      commissionPercent:
          double.tryParse(json['commission_percent']?.toString() ?? '') ?? 0,
      commissionAmount:
          double.tryParse(json['commission_amount']?.toString() ?? '') ?? 0,
      bookedAt: json['booked_at'] != null && json['booked_at'] is String
          ? DateTime.parse(json['booked_at'] as String)
          : DateTime.now(),
    );
  }
}

class ProfitExcursion {
  const ProfitExcursion({
    required this.id,
    required this.title,
    required this.dateTime,
  });

  final int id;
  final String title;
  final DateTime dateTime;

  factory ProfitExcursion.fromJson(Map<String, dynamic> json) {
    final dateTimeStr = json['date_time'];
    final dateTime = dateTimeStr != null && dateTimeStr is String
        ? DateTime.parse(dateTimeStr)
        : DateTime.now();
    return ProfitExcursion(
      id: (json['id'] as num?)?.toInt() ?? 0,
      title: json['title'] as String? ?? '',
      dateTime: dateTime,
    );
  }
}

class ProfitTotals {
  const ProfitTotals({
    required this.sales,
    required this.commission,
  });

  final double sales;
  final double commission;
}
