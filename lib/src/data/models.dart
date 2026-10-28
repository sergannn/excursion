import 'package:hive/hive.dart';

enum UserRole { admin, seller, partnerSeller, driver, guide }

enum PassengerType { adult, child, disabled, senior }

enum BookingStatus { confirmed, cancelled }

enum PriceTier { standard, upTo15, upTo10, upTo5 }

class UserProfile {
  UserProfile({
    required this.id,
    required this.displayName,
    required this.shortName,
    required this.role,
    required this.login,
    required this.password,
    this.balance = 0,
  });

  String id;
  String displayName;
  String shortName;
  UserRole role;
  String login;
  String password;
  double balance;

  UserProfile copyWith({
    double? balance,
  }) {
    return UserProfile(
      id: id,
      displayName: displayName,
      shortName: shortName,
      role: role,
      login: login,
      password: password,
      balance: balance ?? this.balance,
    );
  }
}

class Excursion {
  Excursion({
    required this.id,
    required this.title,
    required this.dateTime,
    required this.stopIds,
    required this.driverIds,
    required this.guideIds,
    required this.guideRequired,
    this.baseCapacity = 21,
  });

  String id;
  String title;
  DateTime dateTime;
  List<String> stopIds;
  List<String> driverIds;
  List<String> guideIds;
  bool guideRequired;
  int baseCapacity;

  Excursion copyWith({
    List<String>? driverIds,
    List<String>? guideIds,
    bool? guideRequired,
    DateTime? dateTime,
  }) {
    return Excursion(
      id: id,
      title: title,
      dateTime: dateTime ?? this.dateTime,
      stopIds: stopIds,
      driverIds: driverIds ?? this.driverIds,
      guideIds: guideIds ?? this.guideIds,
      guideRequired: guideRequired ?? this.guideRequired,
      baseCapacity: baseCapacity,
    );
  }
}

class Booking {
  Booking({
    required this.id,
    required this.excursionId,
    required this.sellerId,
    required this.passengerType,
    required this.stopId,
    required this.price,
    required this.status,
    required this.createdAt,
    this.seatNumber,
  });

  String id;
  String excursionId;
  String sellerId;
  int? seatNumber;
  PassengerType passengerType;
  String stopId;
  double price;
  BookingStatus status;
  DateTime createdAt;

  Booking copyWith({
    BookingStatus? status,
  }) {
    return Booking(
      id: id,
      excursionId: excursionId,
      sellerId: sellerId,
      passengerType: passengerType,
      stopId: stopId,
      price: price,
      status: status ?? this.status,
      createdAt: createdAt,
      seatNumber: seatNumber,
    );
  }
}

class WalletTransaction {
  WalletTransaction({
    required this.id,
    required this.userId,
    required this.amount,
    required this.description,
    required this.timestamp,
    this.bookingId,
  });

  String id;
  String userId;
  double amount;
  String description;
  DateTime timestamp;
  String? bookingId;
}

class PriceRule {
  PriceRule({
    required this.id,
    required this.excursionId,
    required this.tier,
    required this.sellerPayout,
    required this.driverPayout,
    required this.guidePayout,
  });

  String id;
  String excursionId;
  PriceTier tier;
  double sellerPayout;
  double driverPayout;
  double guidePayout;
}

class StopPoint {
  StopPoint({
    required this.id,
    required this.name,
  });

  String id;
  String name;
}

class UserRoleAdapter extends TypeAdapter<UserRole> {
  @override
  final int typeId = 1;

  @override
  UserRole read(BinaryReader reader) {
    final index = reader.readByte();
    return UserRole.values[index];
  }

  @override
  void write(BinaryWriter writer, UserRole obj) {
    writer.writeByte(obj.index);
  }
}

class PassengerTypeAdapter extends TypeAdapter<PassengerType> {
  @override
  final int typeId = 2;

  @override
  PassengerType read(BinaryReader reader) {
    final index = reader.readByte();
    return PassengerType.values[index];
  }

  @override
  void write(BinaryWriter writer, PassengerType obj) {
    writer.writeByte(obj.index);
  }
}

class BookingStatusAdapter extends TypeAdapter<BookingStatus> {
  @override
  final int typeId = 3;

  @override
  BookingStatus read(BinaryReader reader) {
    final index = reader.readByte();
    return BookingStatus.values[index];
  }

  @override
  void write(BinaryWriter writer, BookingStatus obj) {
    writer.writeByte(obj.index);
  }
}

class PriceTierAdapter extends TypeAdapter<PriceTier> {
  @override
  final int typeId = 4;

  @override
  PriceTier read(BinaryReader reader) {
    final index = reader.readByte();
    return PriceTier.values[index];
  }

  @override
  void write(BinaryWriter writer, PriceTier obj) {
    writer.writeByte(obj.index);
  }
}

class UserProfileAdapter extends TypeAdapter<UserProfile> {
  @override
  final int typeId = 10;

  @override
  UserProfile read(BinaryReader reader) {
    final id = reader.readString();
    final displayName = reader.readString();
    final shortName = reader.readString();
    final role = reader.read() as UserRole;
    final login = reader.readString();
    final password = reader.readString();
    final balance = reader.readDouble();
    return UserProfile(
      id: id,
      displayName: displayName,
      shortName: shortName,
      role: role,
      login: login,
      password: password,
      balance: balance,
    );
  }

  @override
  void write(BinaryWriter writer, UserProfile obj) {
    writer
      ..writeString(obj.id)
      ..writeString(obj.displayName)
      ..writeString(obj.shortName)
      ..write(obj.role)
      ..writeString(obj.login)
      ..writeString(obj.password)
      ..writeDouble(obj.balance);
  }
}

class ExcursionAdapter extends TypeAdapter<Excursion> {
  @override
  final int typeId = 11;

  @override
  Excursion read(BinaryReader reader) {
    final id = reader.readString();
    final title = reader.readString();
    final dateTime = DateTime.fromMillisecondsSinceEpoch(reader.readInt());
    final stopIds = List<String>.from(reader.readList());
    final driverIds = List<String>.from(reader.readList());
    final guideIds = List<String>.from(reader.readList());
    final guideRequired = reader.readBool();
    final baseCapacity = reader.readInt();
    return Excursion(
      id: id,
      title: title,
      dateTime: dateTime,
      stopIds: stopIds,
      driverIds: driverIds,
      guideIds: guideIds,
      guideRequired: guideRequired,
      baseCapacity: baseCapacity,
    );
  }

  @override
  void write(BinaryWriter writer, Excursion obj) {
    writer
      ..writeString(obj.id)
      ..writeString(obj.title)
      ..writeInt(obj.dateTime.millisecondsSinceEpoch)
      ..writeList(obj.stopIds)
      ..writeList(obj.driverIds)
      ..writeList(obj.guideIds)
      ..writeBool(obj.guideRequired)
      ..writeInt(obj.baseCapacity);
  }
}

class BookingAdapter extends TypeAdapter<Booking> {
  @override
  final int typeId = 12;

  @override
  Booking read(BinaryReader reader) {
    final id = reader.readString();
    final excursionId = reader.readString();
    final sellerId = reader.readString();
    final seatNumber = reader.read() as int?;
    final passengerType = reader.read() as PassengerType;
    final stopId = reader.readString();
    final price = reader.readDouble();
    final status = reader.read() as BookingStatus;
    final createdAt = DateTime.fromMillisecondsSinceEpoch(reader.readInt());
    return Booking(
      id: id,
      excursionId: excursionId,
      sellerId: sellerId,
      seatNumber: seatNumber,
      passengerType: passengerType,
      stopId: stopId,
      price: price,
      status: status,
      createdAt: createdAt,
    );
  }

  @override
  void write(BinaryWriter writer, Booking obj) {
    writer
      ..writeString(obj.id)
      ..writeString(obj.excursionId)
      ..writeString(obj.sellerId)
      ..write(obj.seatNumber)
      ..write(obj.passengerType)
      ..writeString(obj.stopId)
      ..writeDouble(obj.price)
      ..write(obj.status)
      ..writeInt(obj.createdAt.millisecondsSinceEpoch);
  }
}

class WalletTransactionAdapter extends TypeAdapter<WalletTransaction> {
  @override
  final int typeId = 13;

  @override
  WalletTransaction read(BinaryReader reader) {
    final id = reader.readString();
    final userId = reader.readString();
    final amount = reader.readDouble();
    final description = reader.readString();
    final timestamp = DateTime.fromMillisecondsSinceEpoch(reader.readInt());
    final bookingId = reader.read() as String?;
    return WalletTransaction(
      id: id,
      userId: userId,
      amount: amount,
      description: description,
      timestamp: timestamp,
      bookingId: bookingId,
    );
  }

  @override
  void write(BinaryWriter writer, WalletTransaction obj) {
    writer
      ..writeString(obj.id)
      ..writeString(obj.userId)
      ..writeDouble(obj.amount)
      ..writeString(obj.description)
      ..writeInt(obj.timestamp.millisecondsSinceEpoch)
      ..write(obj.bookingId);
  }
}

class PriceRuleAdapter extends TypeAdapter<PriceRule> {
  @override
  final int typeId = 14;

  @override
  PriceRule read(BinaryReader reader) {
    final id = reader.readString();
    final excursionId = reader.readString();
    final tier = reader.read() as PriceTier;
    final sellerPayout = reader.readDouble();
    final driverPayout = reader.readDouble();
    final guidePayout = reader.readDouble();
    return PriceRule(
      id: id,
      excursionId: excursionId,
      tier: tier,
      sellerPayout: sellerPayout,
      driverPayout: driverPayout,
      guidePayout: guidePayout,
    );
  }

  @override
  void write(BinaryWriter writer, PriceRule obj) {
    writer
      ..writeString(obj.id)
      ..writeString(obj.excursionId)
      ..write(obj.tier)
      ..writeDouble(obj.sellerPayout)
      ..writeDouble(obj.driverPayout)
      ..writeDouble(obj.guidePayout);
  }
}

class StopPointAdapter extends TypeAdapter<StopPoint> {
  @override
  final int typeId = 15;

  @override
  StopPoint read(BinaryReader reader) {
    final id = reader.readString();
    final name = reader.readString();
    return StopPoint(id: id, name: name);
  }

  @override
  void write(BinaryWriter writer, StopPoint obj) {
    writer
      ..writeString(obj.id)
      ..writeString(obj.name);
  }
}
