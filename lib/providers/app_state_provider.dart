import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/models/user_model.dart';
import '../core/models/product_model.dart';
import '../core/models/restaurant_model.dart';
import '../core/models/cart_item_model.dart';
import '../core/models/order_model.dart';
import '../core/models/address_model.dart';
import '../core/services/firebase_service.dart';
import '../core/services/location_service.dart';
import '../core/constants/app_strings.dart';

class AppStateProvider extends ChangeNotifier {

  // ── Auth ──────────────────────────────────────────────
  UserModel? _user;
  UserModel? get user => _user;
  bool get isLoggedIn => _user != null;

  String? _otpSession;   // 2Factor session string
  String? get otpSession => _otpSession;
  void setOtpSession(String s) { _otpSession = s; }

  // ── Theme ─────────────────────────────────────────────
  bool _isDark = false;
  bool get isDark => _isDark;
  void toggleTheme() {
    _isDark = !_isDark;
    _prefs?.setBool('td_dark', _isDark);
    notifyListeners();
  }

  // ── Location ──────────────────────────────────────────
  String _currentAddress = 'Please add your address';
  String get currentAddress => _currentAddress;
  double _lat = 27.5638;   // Sarai Aghat, Etah default
  double _lng = 78.9674;
  double get lat => _lat;
  double get lng => _lng;
  bool _liveLocationActive = false;
  bool get liveLocationActive => _liveLocationActive;


  Future<void> fetchCurrentLocation() async {
    final pos = await LocationService.getCurrentPosition();
    if (pos != null) {
      _lat = pos.latitude;
      _lng = pos.longitude;
      _liveLocationActive = true;
      _currentAddress = await LocationService.getAddressFromCoords(_lat, _lng);
      notifyListeners();
    }
  }

  void setManualAddress(String address, {double? lat, double? lng}) {
    _currentAddress = address;
    if (lat != null) _lat = lat;
    if (lng != null) _lng = lng;
    notifyListeners();
  }

  // ── Products / Data ───────────────────────────────────
  List<ProductModel>      _products     = [];
  List<ProductModel>      _groceryItems = [];
  List<RestaurantModel>   _restaurants  = [];
  List<Map<String,dynamic>> _categories = [];
  List<Map<String,dynamic>> _banners    = [];
  bool _dataLoaded = false;

  List<ProductModel>        get products     => _products;
  List<ProductModel>        get groceryItems => _groceryItems;
  List<RestaurantModel>     get restaurants  => _restaurants;
  List<Map<String,dynamic>> get categories   => _categories;
  List<Map<String,dynamic>> get banners      => _banners;
  bool                      get dataLoaded   => _dataLoaded;

  Future<void> loadData() async {
    if (AppStrings.firebaseUrl.isEmpty) {
      debugPrint('⚠️ TezDrop ERROR: FB_URL is empty. App was built without --dart-define=FB_URL=... '
          'Firebase calls will all fail silently. Add --dart-define when running/building.');
      _dataLoaded = true;
      notifyListeners();
      return;
    }
    final remote = await FirebaseService.fetchAllData();
    if (remote != null) {
      _parseRemoteData(remote);
    }
    _dataLoaded = true;
    notifyListeners();
  }

  void _parseRemoteData(Map<String, dynamic> d) {
    if (d['products'] is Map || d['products'] is List) {
      final raw = d['products'] is Map
          ? (d['products'] as Map).values
          : (d['products'] as List);
      _products = raw
          .whereType<Map>()
          .map((e) => ProductModel.fromJson(Map<String, dynamic>.from(e)))
          .where((p) => !p.isGrocery)
          .toList();
    }
    if (d['grocery'] is Map || d['grocery'] is List) {
      final raw = d['grocery'] is Map
          ? (d['grocery'] as Map).values
          : (d['grocery'] as List);
      _groceryItems = raw
          .whereType<Map>()
          .map((e) => ProductModel.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }
    if (d['restaurants'] is Map || d['restaurants'] is List) {
      final raw = d['restaurants'] is Map
          ? (d['restaurants'] as Map).values
          : (d['restaurants'] as List);
      _restaurants = raw
          .whereType<Map>()
          .map((e) => RestaurantModel.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }
    if (d['categories'] is Map || d['categories'] is List) {
      final raw = d['categories'] is Map
          ? (d['categories'] as Map).values.toList()
          : (d['categories'] as List);
      _categories = raw.whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e)).toList();
    }
    if (d['banners'] is Map || d['banners'] is List) {
      final raw = d['banners'] is Map
          ? (d['banners'] as Map).values.toList()
          : (d['banners'] as List);
      _banners = raw.whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e)).toList();
    }
  }

  // ── Cart ──────────────────────────────────────────────
  final List<CartItemModel> _cart = [];
  List<CartItemModel> get cart => _cart;
  int get cartCount => _cart.fold(0, (s, i) => s + i.quantity);

  void addToCart(ProductModel p, {List<Map<String, dynamic>> selectedAddOns = const []}) {
    final newItem = CartItemModel(product: p, selectedAddOns: selectedAddOns);
    final idx = _cart.indexWhere((i) => i.cartKey == newItem.cartKey);
    if (idx >= 0) {
      if (_cart[idx].quantity < p.stock) {
        _cart[idx].quantity++;
      }
    } else {
      if (p.stock > 0) {
        _cart.add(newItem);
      }
    }
    _saveCart();
    notifyListeners();
  }

  void removeFromCart(ProductModel p, {List<Map<String, dynamic>> selectedAddOns = const []}) {
    final tempKey = CartItemModel(product: p, selectedAddOns: selectedAddOns).cartKey;
    final idx = _cart.indexWhere((i) => i.cartKey == tempKey);
    if (idx >= 0) {
      if (_cart[idx].quantity > 1) {
        _cart[idx].quantity--;
      } else {
        _cart.removeAt(idx);
      }
    }
    _saveCart();
    notifyListeners();
  }

  void removeProductCompletely(ProductModel p) {
    _cart.removeWhere((i) => i.product.id == p.id);
    _saveCart();
    notifyListeners();
  }

  void clearCart() {
    _cart.clear();
    _discount = 0;
    _appliedCoupon = '';
    _useCoins = false;
    _saveCart();
    notifyListeners();
  }

  int cartQtyFor(String productId) =>
      _cart.where((i) => i.product.id == productId).fold(0, (s, i) => s + i.quantity);

  // ── Bill Calculation ──────────────────────────────────
  double _discount = 0;
  String _appliedCoupon = '';
  bool _useCoins = false;

  double get discount    => _discount;
  String get appliedCoupon => _appliedCoupon;
  bool   get useCoins    => _useCoins;

  double get subtotal =>
      _cart.fold(0.0, (s, i) => s + i.totalPrice);

  int get coinsDiscount {
    if (!_useCoins || _user == null || _user!.coins <= 0) return 0;
    return (_user!.coins).clamp(0, (subtotal * 0.1).floor());
  }

  double get total =>
      (subtotal - _discount - coinsDiscount).clamp(0, double.infinity);

  bool applyCoupon(String code) {
    final up = code.trim().toUpperCase();
    if (AppStrings.coupons.containsKey(up)) {
      final minOrder = AppStrings.couponMinOrder[up] ?? 0;
      if (subtotal < minOrder) return false;
      _discount = AppStrings.coupons[up]!.toDouble();
      _appliedCoupon = up;
      notifyListeners();
      return true;
    }
    return false;
  }

  void removeCoupon() {
    _discount = 0;
    _appliedCoupon = '';
    notifyListeners();
  }

  void toggleUseCoins(bool val) {
    _useCoins = val;
    notifyListeners();
  }

  // ── Addresses ─────────────────────────────────────────
  List<AddressModel> _addresses = [];
  List<AddressModel> get addresses => _addresses;
  AddressModel? _selectedAddress;
  AddressModel? get selectedAddress => _selectedAddress;

  void addAddress(AddressModel addr) {
    _addresses.add(addr);
    _selectedAddress = addr;
    _currentAddress = addr.displayString;
    _saveAddresses();
    notifyListeners();
  }

  void removeAddress(int index) {
    _addresses.removeAt(index);
    if (_addresses.isNotEmpty) {
      _selectedAddress = _addresses.last;
      _currentAddress = _selectedAddress!.displayString;
    } else {
      _selectedAddress = null;
      _currentAddress = 'Please add your address';
    }
    _saveAddresses();
    notifyListeners();
  }

  void selectAddress(int index) {
    _selectedAddress = _addresses[index];
    _currentAddress = _selectedAddress!.displayString;
    notifyListeners();
  }

  // ── Wishlist ──────────────────────────────────────────
  final Set<String> _wishlist = {};
  Set<String> get wishlist => _wishlist;

  bool isWishlisted(String id) => _wishlist.contains(id);

  void toggleWish(String id) {
    if (_wishlist.contains(id)) {
      _wishlist.remove(id);
    } else {
      _wishlist.add(id);
    }
    _saveWishlist();
    notifyListeners();
  }

  List<ProductModel> get wishlistProducts {
    final all = [..._products, ..._groceryItems];
    return all.where((p) => _wishlist.contains(p.id)).toList();
  }

  // ── Orders ────────────────────────────────────────────
  List<OrderModel> _orders = [];
  List<OrderModel> get orders => _orders;
  OrderModel? _lastOrder;
  OrderModel? get lastOrder => _lastOrder;

  Future<bool> placeOrder() async {
    // Live location ya saved address — dono mein se koi ek hona chahiye
    final bool hasAddress = _selectedAddress != null || _liveLocationActive;
    if (_cart.isEmpty || !hasAddress) return false;
    if (_user == null) return false;
    if (AppStrings.firebaseUrl.isEmpty) {
      debugPrint('⚠️ TezDrop ERROR: Cannot place order — FB_URL is empty. '
          'Run/build with --dart-define=FB_URL=https://your-db.firebaseio.com');
      return false;
    }

    final oid = 'TD${(10000 + DateTime.now().millisecondsSinceEpoch % 90000)}';
    // Rider ab yahan assign NAHI hota — order 'rider: empty' ke saath jaata hai,
    // aur asli TezDrop Rider app use accept karke apna naam/phone bharta hai.
    const rider = '';
    const riderPhone = '';
    final earned = (total * 0.01).ceil().clamp(1, 9999);
    final usedCoins = coinsDiscount;

    // Delivery OTP — random 4-digit code only the customer can see. The
    // rider must ask the customer for this and enter it in their app to
    // mark the order as delivered — prevents mistaken/fraudulent handovers.
    final otp = (1000 + math.Random().nextInt(9000)).toString();

    final orderData = OrderModel(
      orderId     : oid,
      phone       : _user!.phone,
      address     : _currentAddress,
      lat         : _lat,
      lng         : _lng,
      items       : _cart.map((i) => OrderItemSnapshot(
        id       : i.product.id,
        name     : i.product.name,
        price    : i.product.price,
        qty      : i.quantity,
        isGrocery: i.product.isGrocery,
        image    : i.product.image,
      )).toList(),
      total       : total,
      status      : 'Confirmed',
      rider       : rider,
      riderPhone  : riderPhone,
      coinsUsed   : usedCoins,
      coinsEarned : earned,
      timestamp   : DateTime.now().toString().substring(0, 19),
      deliveryOtp : otp,
    );

    final key = await FirebaseService.placeOrder(orderData.toJson());
    if (key != null) {
      orderData.firebaseKey = key;
      _lastOrder = orderData;
      // Update user coins
      _user = _user!.copyWith(
        coins: (_user!.coins - usedCoins + earned).clamp(0, 999999),
      );
      _saveUser();
      clearCart();
      return true;
    }
    return false;
  }

  Future<void> loadOrders() async {
    if (_user == null) return;
    _orders = await FirebaseService.loadOrders(_user!.phone);
    notifyListeners();
  }

  // ── Notifications ─────────────────────────────────────
  bool _hasUnread = true;
  bool get hasUnread => _hasUnread;
  void markNotificationsRead() {
    _hasUnread = false;
    notifyListeners();
  }

  // ── Filters ───────────────────────────────────────────
  String _vegFilter    = 'all'; // all | veg | non-veg
  String _sortFilter = 'none'; // 'none' | 'price' | 'rating'
  String _activeTab    = 'food'; // food | grocery
  String _groceryFilter = 'all';

  String get vegFilter     => _vegFilter;
  String get sortFilter => _sortFilter;
  void setSortFilter(String s) { _sortFilter = s; notifyListeners(); }
  String get activeTab     => _activeTab;
  String get groceryFilter => _groceryFilter;

  void setVegFilter(String f)     { _vegFilter = f; notifyListeners(); }
  void setActiveTab(String t)     { _activeTab = t; notifyListeners(); }
  void setGroceryFilter(String f) { _groceryFilter = f; notifyListeners(); }

  List<ProductModel> get filteredProducts {
    var list = _activeTab == 'grocery' ? [..._groceryItems] : [..._products];
    if (_vegFilter == 'veg')     list = list.where((p) => p.type == 'veg').toList();
    if (_vegFilter == 'non-veg') list = list.where((p) => p.type == 'non-veg').toList();
    
    // After veg filtering, apply sort
    if (_sortFilter == 'price') {
      list.sort((a, b) => a.price.compareTo(b.price));
    } else if (_sortFilter == 'rating') {
      list.sort((a, b) => b.rating.compareTo(a.rating));
    }
    
    return list;
  }

  List<ProductModel> get filteredGrocery {
    if (_groceryFilter == 'all') return _groceryItems;
    return _groceryItems
        .where((p) => p.category == _groceryFilter)
        .toList();
  }

  // ── Auth Methods ──────────────────────────────────────
  void loginUser(UserModel u) {
    _user = u;
    _saveUser();
    notifyListeners();
  }

  /// Returns true if this phone is genuinely new (no saved record found),
  /// so the UI can show the correct "+10 bonus" message only when it's real.
  bool createUser(String phone, String name, {String email = ''}) {
    // Check for a previously saved record for this exact phone — this
    // survives logout, so a returning user's real coin balance is restored
    // instead of being reset to a fresh "new user" bonus every login.
    UserModel? existing;
    final existingJson = _prefs?.getString('td_user_$phone');
    if (existingJson != null) {
      try {
        existing = UserModel.fromJson(jsonDecode(existingJson));
      } catch (_) {}
    }

    final bool isNewUser = existing == null;
    final referCode = existing?.referCode ?? 'TEZ${phone.substring(phone.length - 4)}';

    _user = UserModel(
      phone     : phone,
      name      : name.isNotEmpty ? name : (existing?.name ?? name),
      email     : email.isNotEmpty ? email : (existing?.email ?? email),
      coins     : isNewUser ? 10 : existing!.coins,
      referCode : referCode,
      avatarIndex: existing?.avatarIndex ?? 0,
    );
    _saveUser();
    notifyListeners();
    return isNewUser;
  }

  void updateProfile({String? name, String? email, int? avatarIndex}) {
    if (_user == null) return;
    _user = _user!.copyWith(
      name       : name,
      email      : email,
      avatarIndex: avatarIndex,
    );
    _saveUser();
    notifyListeners();
  }

  // FIX #5: Rating submit karne par +5 TezCoins actually award hoti hain
  Future<void> awardRatingCoins() async {
    if (_user == null) return;
    final key = 'last_rating_${_user!.phone}';
    final lastRatingStr = _prefs?.getString(key);
    if (lastRatingStr != null) {
      final lastRating = DateTime.tryParse(lastRatingStr);
      if (lastRating != null && DateTime.now().difference(lastRating).inHours < 24) {
        return; // Already rated in last 24 hours — no coins
      }
    }
    _user = _user!.copyWith(coins: _user!.coins + 5);
    _saveUser();
    _prefs?.setString(key, DateTime.now().toIso8601String());
    notifyListeners();
  }

  void logout() {
    _user = null;
    _prefs?.remove('td_user');
    _cart.clear();
    _wishlist.clear();
    _orders.clear();
    _addresses.clear();
    _prefs?.remove('td_addrs');
    _lastOrder = null;
    notifyListeners();
  }

  // ── SharedPreferences ─────────────────────────────────
  SharedPreferences? _prefs;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    _isDark = _prefs?.getBool('td_dark') ?? false;

    // Load user
    final userJson = _prefs?.getString('td_user');
    if (userJson != null) {
      _user = UserModel.fromJson(jsonDecode(userJson));
    }

    // Load cart
    final cartJson = _prefs?.getString('td_cart');
    if (cartJson != null) {
      // Cart restore after data load (done in main)
      _savedCartJson = cartJson;
    }

    // Load addresses
    final addrJson = _prefs?.getString('td_addrs');
    if (addrJson != null) {
      final list = jsonDecode(addrJson) as List;
      _addresses = list
          .map((e) => AddressModel.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      if (_addresses.isNotEmpty) {
        _selectedAddress = _addresses.last;
        _currentAddress = _selectedAddress!.displayString;
      }
    }

    // Load wishlist
    final wishJson = _prefs?.getStringList('td_wish');
    if (wishJson != null) _wishlist.addAll(wishJson);

    notifyListeners();
  }

  String? _savedCartJson;

  void restoreCartAfterLoad() {
    if (_savedCartJson == null) return;
    try {
      final list = jsonDecode(_savedCartJson!) as List;
      for (final item in list) {
        final pid = item['id']?.toString() ?? '';
        final isG = item['isGrocery'] ?? false;
        final qty = (item['qty'] as num?)?.toInt() ?? 1;
        final src = isG ? _groceryItems : _products;
        final prod = src.where((p) => p.id == pid).firstOrNull;
        if (prod != null) {
          final savedAddOns = (item['selectedAddOns'] as List?)
              ?.whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList() ?? [];
          for (int i = 0; i < qty; i++) {
            addToCart(prod, selectedAddOns: savedAddOns);
          }
        }
      }
    } catch (_) {}
    _savedCartJson = null;
  }

  void _saveUser() {
    if (_user != null) {
      final json = jsonEncode(_user!.toJson());
      _prefs?.setString('td_user', json);
      // Phone-keyed backup — survives logout, so a returning user's real
      // coin balance can be restored instead of resetting to a "new user".
      _prefs?.setString('td_user_${_user!.phone}', json);
    }
  }

  void _saveCart() {
    final list = _cart.map((i) => i.toJson()).toList();
    _prefs?.setString('td_cart', jsonEncode(list));
  }

  void _saveAddresses() {
    final list = _addresses.map((a) => a.toJson()).toList();
    _prefs?.setString('td_addrs', jsonEncode(list));
  }

  void _saveWishlist() {
    _prefs?.setStringList('td_wish', _wishlist.toList());
  }

}
