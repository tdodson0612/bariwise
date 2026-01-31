//lib/models/grocery_item.dart
class GroceryItem {
  final int? id;
  final String userId;
  final String item;
  final int orderIndex;
  final DateTime createdAt;

  GroceryItem({
    this.id,
    required this.userId,
    required this.item,
    required this.orderIndex,
    required this.createdAt,
  });

  factory GroceryItem.fromJson(Map<String, dynamic> json) {
    return GroceryItem(
      id: json['id'],
      userId: json['user_id'],
      item: json['item'],
      orderIndex: json['order_index'],
      createdAt: DateTime.parse(json['created_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'user_id': userId,
      'item': item,
      'order_index': orderIndex,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
