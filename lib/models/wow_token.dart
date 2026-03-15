import 'package:intl/intl.dart';

/// WoW Token price data from the Game Data API.
class WowToken {
  final int price;
  final int lastUpdatedTimestamp;

  const WowToken({
    required this.price,
    required this.lastUpdatedTimestamp,
  });

  factory WowToken.fromJson(Map<String, dynamic> json) {
    return WowToken(
      price: json['price'] as int,
      lastUpdatedTimestamp: json['last_updated_timestamp'] as int,
    );
  }

  /// Price converted from copper to gold (divide by 10,000).
  int get priceInGold => price ~/ 10000;

  /// Price formatted with comma separators (e.g., "234,500").
  String get formattedPrice => NumberFormat('#,###').format(priceInGold);

  /// Timestamp as DateTime.
  DateTime get lastUpdated =>
      DateTime.fromMillisecondsSinceEpoch(lastUpdatedTimestamp);
}
