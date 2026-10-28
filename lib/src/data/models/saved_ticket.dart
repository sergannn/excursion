class SavedTicket {
  final int bookingId;
  final String ticketNumber;
  final String excursionTitle;
  final String excursionDate;
  final String stopName;
  final String customerName;
  final String customerPhone;
  final String fileName;
  final DateTime savedAt;
  final int seatCount;
  final double totalAmount;

  SavedTicket({
    required this.bookingId,
    required this.ticketNumber,
    required this.excursionTitle,
    required this.excursionDate,
    required this.stopName,
    required this.customerName,
    required this.customerPhone,
    required this.fileName,
    required this.savedAt,
    required this.seatCount,
    required this.totalAmount,
  });

  Map<String, dynamic> toJson() {
    return {
      'bookingId': bookingId,
      'ticketNumber': ticketNumber,
      'excursionTitle': excursionTitle,
      'excursionDate': excursionDate,
      'stopName': stopName,
      'customerName': customerName,
      'customerPhone': customerPhone,
      'fileName': fileName,
      'savedAt': savedAt.toIso8601String(),
      'seatCount': seatCount,
      'totalAmount': totalAmount,
    };
  }

  factory SavedTicket.fromJson(Map<String, dynamic> json) {
    return SavedTicket(
      bookingId: json['bookingId'] as int,
      ticketNumber: json['ticketNumber'] as String,
      excursionTitle: json['excursionTitle'] as String,
      excursionDate: json['excursionDate'] as String,
      stopName: json['stopName'] as String,
      customerName: json['customerName'] as String,
      customerPhone: json['customerPhone'] as String,
      fileName: json['fileName'] as String,
      savedAt: DateTime.parse(json['savedAt'] as String),
      seatCount: json['seatCount'] as int,
      totalAmount: (json['totalAmount'] as num).toDouble(),
    );
  }
}
