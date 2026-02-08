// lib/models/grocery_item.dart
// ✅ FIXED: Uses correct column name "item_name" instead of "item"

class GroceryItem {
  final int? id;
  final String userId;
  final String item;  // Still called "item" in the model for backwards compatibility
  final int orderIndex;
  final DateTime createdAt;

  GroceryItem({
    this.id,
    required this.userId,
    required this.item,
    required this.orderIndex,
    required this.createdAt,
  });

  /// ✅ FIXED: Maps "item_name" from database to "item" in model
  factory GroceryItem.fromJson(Map<String, dynamic> json) {
    try {
      return GroceryItem(
        id: json['id'] as int?,
        userId: json['user_id']?.toString() ?? '',
        item: json['item_name']?.toString() ?? '', // ✅ Changed from 'item' to 'item_name'
        orderIndex: json['order_index'] as int? ?? 0,
        createdAt: json['created_at'] != null 
            ? DateTime.parse(json['created_at'].toString())
            : DateTime.now(),
      );
    } catch (e) {
      print('❌ Error parsing GroceryItem from JSON: $e');
      print('JSON data: $json');
      
      return GroceryItem(
        id: null,
        userId: json['user_id']?.toString() ?? '',
        item: json['item_name']?.toString() ?? 'Unknown Item', // ✅ Changed
        orderIndex: 0,
        createdAt: DateTime.now(),
      );
    }
  }

  /// ✅ FIXED: Maps "item" in model to "item_name" in database
  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'user_id': userId,
      'item_name': item,  // ✅ Changed from 'item' to 'item_name'
      'order_index': orderIndex,
      'created_at': createdAt.toIso8601String(),
    };
  }

  bool isValid() {
    return userId.isNotEmpty && item.isNotEmpty;
  }

  GroceryItem copyWith({
    int? id,
    String? userId,
    String? item,
    int? orderIndex,
    DateTime? createdAt,
  }) {
    return GroceryItem(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      item: item ?? this.item,
      orderIndex: orderIndex ?? this.orderIndex,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  String toString() {
    return 'GroceryItem(id: $id, userId: $userId, item: $item, orderIndex: $orderIndex)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is GroceryItem &&
        other.id == id &&
        other.userId == userId &&
        other.item == item &&
        other.orderIndex == orderIndex;
  }

  @override
  int get hashCode {
    return Object.hash(id, userId, item, orderIndex);
  }
}