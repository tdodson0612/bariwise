// lib/models/grocery_item.dart
// ✅ Adds "category" and "checked" fields, backed by new DB columns:
//    category (text, default 'Other'), checked (boolean, default false)

class GroceryItem {
  final int? id;
  final String userId;
  final String item; // kept as "item" for backwards compatibility
  final int orderIndex;
  final DateTime createdAt;
  final String category;
  final bool checked;

  GroceryItem({
    this.id,
    required this.userId,
    required this.item,
    required this.orderIndex,
    required this.createdAt,
    this.category = 'Other',
    this.checked = false,
  });

  /// Maps "item_name" -> "item", plus "category" and "checked" straight through.
  factory GroceryItem.fromJson(Map<String, dynamic> json) {
    try {
      return GroceryItem(
        id: json['id'] as int?,
        userId: json['user_id']?.toString() ?? '',
        item: json['item_name']?.toString() ?? '',
        orderIndex: json['order_index'] as int? ?? 0,
        createdAt: json['created_at'] != null
            ? DateTime.parse(json['created_at'].toString())
            : DateTime.now(),
        category: (json['category']?.toString().trim().isNotEmpty ?? false)
            ? json['category'].toString().trim()
            : 'Other',
        checked: json['checked'] == true ||
            json['checked'] == 1 ||
            json['checked']?.toString().toLowerCase() == 'true',
      );
    } catch (e) {

      return GroceryItem(
        id: null,
        userId: json['user_id']?.toString() ?? '',
        item: json['item_name']?.toString() ?? 'Unknown Item',
        orderIndex: 0,
        createdAt: DateTime.now(),
        category: 'Other',
        checked: false,
      );
    }
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'user_id': userId,
      'item_name': item,
      'order_index': orderIndex,
      'created_at': createdAt.toIso8601String(),
      'category': category,
      'checked': checked,
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
    String? category,
    bool? checked,
  }) {
    return GroceryItem(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      item: item ?? this.item,
      orderIndex: orderIndex ?? this.orderIndex,
      createdAt: createdAt ?? this.createdAt,
      category: category ?? this.category,
      checked: checked ?? this.checked,
    );
  }

  @override
  String toString() {
    return 'GroceryItem(id: $id, userId: $userId, item: $item, orderIndex: $orderIndex, category: $category, checked: $checked)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is GroceryItem &&
        other.id == id &&
        other.userId == userId &&
        other.item == item &&
        other.orderIndex == orderIndex &&
        other.category == category &&
        other.checked == checked;
  }

  @override
  int get hashCode {
    return Object.hash(id, userId, item, orderIndex, category, checked);
  }
}