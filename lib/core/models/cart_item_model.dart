import 'product_model.dart';

class CartItemModel {
  final ProductModel product;
  int quantity;
  // User ne jo addOns select kiye: [{name:'Extra Cheese', price:30}]
  final List<Map<String, dynamic>> selectedAddOns;
  // Grocery items ke liye — konsa weight variant select kiya:
  // {weight:'500g', price:80}. Null matlab product ka normal/base price use hoga.
  final Map<String, dynamic>? selectedVariant;

  CartItemModel({
    required this.product,
    this.quantity = 1,
    this.selectedAddOns = const [],
    this.selectedVariant,
  });

  double get addOnsTotal =>
      selectedAddOns.fold(0.0, (sum, a) => sum + ((a['price'] as num?)?.toDouble() ?? 0.0));

  double get basePrice =>
      selectedVariant != null ? (selectedVariant!['price'] as num).toDouble() : product.price;

  double get unitPrice   => basePrice + addOnsTotal;
  double get totalPrice  => unitPrice * quantity;

  // Cart key: same product + same weight + same addOns = same cart slot
  String get cartKey {
    final variantPart = selectedVariant != null ? '__${selectedVariant!['weight']}' : '';
    if (selectedAddOns.isEmpty) return '${product.id}$variantPart';
    final addOnNames = selectedAddOns.map((a) => a['name']).join('+');
    return '${product.id}$variantPart__$addOnNames';
  }

  String get displayName {
    var name = product.name;
    if (selectedVariant != null) name = '$name (${selectedVariant!['weight']})';
    if (selectedAddOns.isNotEmpty) {
      final addOnNames = selectedAddOns.map((a) => a['name']).join(', ');
      name = '$name (+$addOnNames)';
    }
    return name;
  }

  Map<String, dynamic> toJson() => {
    'id'          : product.id,
    'name'        : displayName,
    'price'       : unitPrice,
    'qty'         : quantity,
    'isGrocery'   : product.isGrocery,
    'image'       : product.image,
    'selectedAddOns': selectedAddOns,
    if (selectedVariant != null) 'selectedVariant': selectedVariant,
  };
}
