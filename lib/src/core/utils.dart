import 'dart:math';

final _random = Random();

String generateId({String prefix = 'id'}) {
  final rand = List.generate(6, (_) => _random.nextInt(36))
      .map((value) => value.toRadixString(36))
      .join();
  return '$prefix-$rand';
}
