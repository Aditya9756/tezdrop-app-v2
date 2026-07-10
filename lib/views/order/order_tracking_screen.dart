import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/constants/app_colors.dart';
import '../../core/services/location_service.dart';
import '../../core/services/firebase_service.dart';

class OrderTrackingScreen extends StatefulWidget {
  final String orderId, riderName, riderPhone;
  const OrderTrackingScreen({
    super.key,
    required this.orderId,
    required this.riderName,
    required this.riderPhone,
  });
  @override
  State<OrderTrackingScreen> createState() => _OrderTrackingScreenState();
}

class _OrderTrackingScreenState extends State<OrderTrackingScreen>
    with TickerProviderStateMixin {

  // ── WebView ──────────────────────────────────────────────────────────────
  late final WebViewController _webCtrl;
  bool _mapReady = false;

  // ── Location ─────────────────────────────────────────────────────────────
  double? _userLat, _userLng;
  double? _riderLat, _riderLng;
  bool _hasRiderFix = false;

  // ── Bike smooth animation ─────────────────────────────────────────────────
  // We animate from the old rider position to the new one over 1 second
  // so the bike icon on the map slides smoothly instead of jumping.
  double? _animFromLat, _animFromLng;
  double? _animToLat, _animToLng;
  late AnimationController _bikeAnimCtrl;
  late Animation<double> _bikeAnim;

  // ── Rider info — starts from the navigation snapshot, then kept live
  // by polling the same node the Rider app writes to.
  late String _riderName;
  late String _riderPhone;

  // ── Order status ──────────────────────────────────────────────────────────
  String _orderStatus = 'Placed';
  static const List<String> _statusOrder = ['Placed','Preparing','Packed','On Way','Delivered'];

  // ── Pollers ───────────────────────────────────────────────────────────────
  Timer? _statusTimer;
  Timer? _riderTimer;

  @override
  void initState() {
    super.initState();
    _riderName = widget.riderName;
    _riderPhone = widget.riderPhone;

    // Smooth bike animation controller — 1 second per position update
    _bikeAnimCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _bikeAnim = CurvedAnimation(parent: _bikeAnimCtrl, curve: Curves.easeInOut);

    _bikeAnimCtrl.addListener(_onBikeAnimTick);

    _initWebView();
    _loadUserLocation();
    _startPolling();
  }

  @override
  void dispose() {
    _bikeAnimCtrl.dispose();
    _statusTimer?.cancel();
    _riderTimer?.cancel();
    super.dispose();
  }

  // ── WebView setup ────────────────────────────────────────────────────────
  void _initWebView() {
    _webCtrl = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) {
          setState(() => _mapReady = true);
          _refreshMap();
        },
      ))
      ..loadHtmlString(_buildMapHtml(), baseUrl: 'https://tezdrop.app/');
  }

  /// Builds the full HTML page with an embedded Google Maps iframe.
  /// When we have coordinates we append them as a directions URL;
  /// otherwise we load a generic map of India.
  String _buildMapHtml({double? uLat, double? uLng, double? rLat, double? rLng}) {
    String mapSrc;
    if (uLat != null && rLat != null) {
      // Directions from rider to user — shows the route on Google Maps
      mapSrc = 'https://www.google.com/maps/embed/v1/directions'
          '?key=AIzaSyD-placeholder'   // no key needed for basic embed
          '&origin=$rLat,$rLng'
          '&destination=$uLat,$uLng'
          '&mode=driving';
      // Fallback: use the simple search embed which needs no API key
      mapSrc = 'https://maps.google.com/maps'
          '?q=$rLat,$rLng'
          '&z=15'
          '&output=embed';
    } else if (uLat != null) {
      mapSrc = 'https://maps.google.com/maps'
          '?q=$uLat,$uLng'
          '&z=15'
          '&output=embed';
    } else {
      mapSrc = 'https://maps.google.com/maps?q=India&z=5&output=embed';
    }

    return '''
<!DOCTYPE html>
<html>
<head>
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <style>
    * { margin:0; padding:0; box-sizing:border-box; }
    body { width:100vw; height:100vh; overflow:hidden; }
    iframe { width:100%; height:100%; border:none; }
  </style>
</head>
<body>
  <iframe
    src="$mapSrc"
    allowfullscreen
    loading="lazy"
    referrerpolicy="no-referrer-when-downgrade">
  </iframe>
</body>
</html>
''';
  }

  void _refreshMap() {
    if (!_mapReady) return;
    _webCtrl.loadHtmlString(_buildMapHtml(
      uLat: _userLat, uLng: _userLng,
      rLat: _riderLat, rLng: _riderLng,
    ), baseUrl: 'https://tezdrop.app/');
  }

  // ── User location ─────────────────────────────────────────────────────────
  Future<void> _loadUserLocation() async {
    final pos = await LocationService.getCurrentPosition();
    if (pos != null && mounted) {
      setState(() { _userLat = pos.latitude; _userLng = pos.longitude; });
      _refreshMap();
    }
  }

  // ── Polling ───────────────────────────────────────────────────────────────
  void _startPolling() {
    _pollStatus();
    _pollRider();
    _statusTimer = Timer.periodic(const Duration(seconds: 6),  (_) => _pollStatus());
    _riderTimer  = Timer.periodic(const Duration(seconds: 4),  (_) => _pollRider());
  }

  Future<void> _pollStatus() async {
    final info = await FirebaseService.getOrderLiveInfo(widget.orderId);
    if (!mounted || info == null) return;

    final status = info['status'] as String?;
    if (status != null && _statusOrder.contains(status) && status != _orderStatus) {
      setState(() => _orderStatus = status);
    }

    final riderName = (info['riderName'] as String?) ?? '';
    final riderPhone = (info['riderPhone'] as String?) ?? '';
    if (riderName.isNotEmpty && riderName != _riderName) {
      setState(() { _riderName = riderName; _riderPhone = riderPhone; });
    }
  }

  Future<void> _pollRider() async {
    final d = await FirebaseService.getRiderLocation(widget.orderId);
    if (!mounted || d == null) return;
    final lat = (d['lat'] as num?)?.toDouble();
    final lng = (d['lng'] as num?)?.toDouble();
    if (lat == null || lng == null) return;

    if (_hasRiderFix && _riderLat != null && _riderLng != null) {
      // Animate smoothly from old position to new
      _animFromLat = _riderLat;
      _animFromLng = _riderLng;
      _animToLat   = lat;
      _animToLng   = lng;
      _bikeAnimCtrl.forward(from: 0);
    } else {
      // First fix — place immediately
      setState(() {
        _riderLat = lat;
        _riderLng = lng;
        _hasRiderFix = true;
      });
      _refreshMap();
    }
  }

  /// Called every animation tick — interpolates the rider's position
  /// between the old and new coordinates for a smooth sliding effect.
  void _onBikeAnimTick() {
    if (_animFromLat == null || _animToLat == null) return;
    final t = _bikeAnim.value;
    final lat = _animFromLat! + (_animToLat! - _animFromLat!) * t;
    final lng = _animFromLng! + (_animToLng! - _animFromLng!) * t;
    setState(() { _riderLat = lat; _riderLng = lng; });
    // Refresh the map every ~10 frames so the iframe follows the position
    if ((_bikeAnimCtrl.value * 10).round() % 2 == 0) _refreshMap();
  }

  double _bearing() {
    if (_animFromLat == null || _animToLat == null) return 0;
    final lat1 = _animFromLat! * math.pi / 180;
    final lat2 = _animToLat!  * math.pi / 180;
    final dLon = (_animToLng! - _animFromLng!) * math.pi / 180;
    final y = math.sin(dLon) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) - math.sin(lat1) * math.cos(lat2) * math.cos(dLon);
    return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
  }

  // ── UI ────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final mapHeight = MediaQuery.of(context).size.height * 0.42;

    return Scaffold(
      body: Column(children: [
        // ── Map + bike overlay ──────────────────────────────────────────────
        SizedBox(
          height: mapHeight,
          child: Stack(children: [
            // Google Maps WebView
            WebViewWidget(controller: _webCtrl),

            // Loading indicator while page loads
            if (!_mapReady)
              const Center(child: CircularProgressIndicator()),

            // Animated bike overlay (floating on top of the WebView)
            // The bike icon is positioned in the CENTRE of the map box when
            // we have a rider fix, to represent the rider's current position
            // visually. (Full pixel-perfect GPS→screen coordinate mapping
            // requires the Maps JS SDK; this approach gives a clear animated
            // indicator without needing an API key.)
            if (_hasRiderFix)
              AnimatedBuilder(
                animation: _bikeAnim,
                builder: (_, __) {
                  return Center(
                    child: Transform.rotate(
                      angle: _bearing() * math.pi / 180,
                      child: Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                          boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.4), blurRadius: 12, spreadRadius: 2)],
                        ),
                        child: const Center(child: Text('🛵', style: TextStyle(fontSize: 26))),
                      ),
                    ),
                  );
                },
              ),

            // Connecting overlay when no rider fix yet
            if (!_hasRiderFix)
              Positioned.fill(
                child: Container(
                  color: Colors.black.withOpacity(0.22),
                  child: Center(
                    child: Card(
                      margin: const EdgeInsets.symmetric(horizontal: 32),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      child: const Padding(
                        padding: EdgeInsets.all(16),
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          CircularProgressIndicator(strokeWidth: 2),
                          SizedBox(height: 10),
                          Text('Waiting for rider to share location...', textAlign: TextAlign.center, style: TextStyle(fontSize: 12)),
                        ]),
                      ),
                    ),
                  ),
                ),
              ),

            // Back button
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              left: 12,
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  width: 38, height: 38,
                  decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 8)]),
                  child: const Icon(Icons.arrow_back, size: 20),
                ),
              ),
            ),

            // LIVE / CONNECTING badge
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              right: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: _hasRiderFix ? AppColors.green : AppColors.textLight,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  _hasRiderFix ? '🟢 LIVE' : 'CONNECTING...',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                ),
              ),
            ),
          ]),
        ),

        // ── Bottom info panel ───────────────────────────────────────────────
        Expanded(
          child: Container(
            color: Theme.of(context).colorScheme.surface,
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                // Status + order id
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(_orderStatus, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.primary)),
                    Text('Order #${widget.orderId}', style: const TextStyle(fontSize: 12, color: AppColors.textGrey)),
                  ]),
                  Container(
                    width: 46, height: 46,
                    decoration: BoxDecoration(color: const Color(0xFFF0FDF4), shape: BoxShape.circle, border: Border.all(color: const Color(0xFFBBF7D0), width: 2)),
                    child: const Icon(Icons.motorcycle, color: AppColors.green, size: 22),
                  ),
                ]),
                const SizedBox(height: 16),

                // Progress stepper
                Row(
                  children: _statusOrder.asMap().entries.map((e) {
                    final i = e.key; final step = e.value;
                    final done   = _statusOrder.indexOf(step) < _statusOrder.indexOf(_orderStatus);
                    final active = step == _orderStatus;
                    return Expanded(child: Row(children: [
                      Expanded(child: Column(children: [
                        Container(
                          width: 28, height: 28,
                          decoration: BoxDecoration(
                            color: done ? AppColors.green : active ? AppColors.primary : AppColors.border,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(_iconFor(step), color: (done || active) ? Colors.white : AppColors.textLight, size: 13),
                        ),
                        const SizedBox(height: 3),
                        Text(step, style: TextStyle(fontSize: 7, fontWeight: FontWeight.bold,
                          color: done ? AppColors.green : active ? AppColors.primary : AppColors.textLight), textAlign: TextAlign.center),
                      ])),
                      if (i < _statusOrder.length - 1)
                        Expanded(child: Container(height: 2, margin: const EdgeInsets.only(bottom: 16), color: done ? AppColors.green : AppColors.border)),
                    ]));
                  }).toList(),
                ),
                const SizedBox(height: 16),

                // Rider card
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: const Color(0xFFF9FAFB), borderRadius: BorderRadius.circular(14)),
                  child: Row(children: [
                    const CircleAvatar(backgroundColor: AppColors.border, child: Text('🧑')),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(_riderName.isEmpty ? 'Assigning rider...' : _riderName,
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      const Text('⭐ Delivery Support', style: TextStyle(fontSize: 11, color: AppColors.textGrey)),
                    ])),
                    if (_riderPhone.isNotEmpty)
                      GestureDetector(
                        onTap: () async {
                          try {
                            await launchUrl(Uri.parse('tel:$_riderPhone'), mode: LaunchMode.externalApplication);
                          } catch (_) {}
                        },
                        child: Container(
                          width: 40, height: 40,
                          decoration: const BoxDecoration(color: Color(0xFFF0FDF4), shape: BoxShape.circle),
                          child: const Icon(Icons.phone, color: AppColors.green, size: 18),
                        ),
                      ),
                  ]),
                ),

                const SizedBox(height: 12),

                // Rider GPS info
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: const Color(0xFFEFF6FF), borderRadius: BorderRadius.circular(12)),
                  child: Row(children: [
                    const Icon(Icons.location_on, color: AppColors.primary, size: 14),
                    const SizedBox(width: 6),
                    Expanded(child: Text(
                      _hasRiderFix && _riderLat != null
                          ? 'Rider live • ${_riderLat!.toStringAsFixed(4)}, ${_riderLng!.toStringAsFixed(4)}'
                          : 'Waiting for rider GPS...',
                      style: const TextStyle(fontSize: 11, color: AppColors.primary),
                    )),
                  ]),
                ),
              ],
            ),
          ),
        ),
      ]),
    );
  }

  IconData _iconFor(String step) {
    switch (step) {
      case 'Placed':    return Icons.check;
      case 'Preparing': return Icons.local_fire_department;
      case 'Packed':    return Icons.inventory_2;
      case 'On Way':    return Icons.motorcycle;
      case 'Delivered': return Icons.home;
      default:          return Icons.circle;
    }
  }
}
