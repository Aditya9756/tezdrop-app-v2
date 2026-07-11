import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:shimmer/shimmer.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/constants/app_colors.dart';
import '../../core/services/location_service.dart';
import '../../core/services/firebase_service.dart';
import '../../core/services/road_route_service.dart';

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

  // ── Map (OpenStreetMap via flutter_map — same approach as address picker,
  // no API key needed, renders real tiles reliably) ──────────────────────────
  final MapController _mapController = MapController();
  bool _mapReady = false;
  List<LatLng> _routePoints = [];

  // ── Location ─────────────────────────────────────────────────────────────
  double? _userLat, _userLng;
  double? _riderLat, _riderLng;
  bool _hasRiderFix = false;

  // ── Bike smooth animation ─────────────────────────────────────────────────
  // We animate from the old rider position to the new one over 1 second
  // so the bike marker slides smoothly instead of jumping.
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
  String _deliveryOtp = '';
  bool _statusLoaded = false;
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

  // ── User location ─────────────────────────────────────────────────────────
  Future<void> _loadUserLocation() async {
    final pos = await LocationService.getCurrentPosition();
    if (pos != null && mounted) {
      setState(() { _userLat = pos.latitude; _userLng = pos.longitude; });
      _fitMapToPoints();
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
    if (!mounted) return;
    if (!_statusLoaded) setState(() => _statusLoaded = true);
    if (info == null) return;

    final status = info['status'] as String?;
    if (status != null && _statusOrder.contains(status) && status != _orderStatus) {
      setState(() => _orderStatus = status);
    }

    final riderName = (info['riderName'] as String?) ?? '';
    final riderPhone = (info['riderPhone'] as String?) ?? '';
    if (riderName.isNotEmpty && riderName != _riderName) {
      setState(() { _riderName = riderName; _riderPhone = riderPhone; });
    }

    final otp = (info['deliveryOtp'] as String?) ?? '';
    if (otp.isNotEmpty && otp != _deliveryOtp) {
      setState(() => _deliveryOtp = otp);
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
      _fitMapToPoints();
    }
  }

  /// Called every animation tick — interpolates the rider's position
  /// between the old and new coordinates for a smooth sliding effect.
  /// flutter_map's MarkerLayer picks this up automatically via setState,
  /// no manual iframe/HTML reload needed.
  void _onBikeAnimTick() {
    if (_animFromLat == null || _animToLat == null) return;
    final t = _bikeAnim.value;
    final lat = _animFromLat! + (_animToLat! - _animFromLat!) * t;
    final lng = _animFromLng! + (_animToLng! - _animFromLng!) * t;
    setState(() { _riderLat = lat; _riderLng = lng; });
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

  /// Moves/zooms the real map camera so both the customer and rider
  /// (whichever are known) are visible. Uses flutter_map's own camera
  /// fitting — real projection, not a manual screen-space hack.
  void _fitMapToPoints() {
    if (!_mapReady) return;
    final points = <LatLng>[];
    if (_userLat != null && _userLng != null) points.add(LatLng(_userLat!, _userLng!));
    if (_riderLat != null && _riderLng != null) points.add(LatLng(_riderLat!, _riderLng!));
    if (points.isEmpty) return;
    if (points.length == 1) {
      _mapController.move(points.first, 15);
      return;
    }
    final bounds = LatLngBounds.fromPoints(points);
    _mapController.fitCamera(
      CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(60)),
    );
    _loadRoute();
  }

  /// Fetches the real road path between rider and customer (OSRM), same
  /// service the Rider app already uses successfully.
  Future<void> _loadRoute() async {
    if (_userLat == null || _riderLat == null) return;
    final path = await RoadRouteService.getRoadPath(
      LatLng(_riderLat!, _riderLng!),
      LatLng(_userLat!, _userLng!),
    );
    if (mounted) setState(() => _routePoints = path);
  }

  // ── UI ────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final mapHeight = MediaQuery.of(context).size.height * 0.42;
    final userPoint = (_userLat != null && _userLng != null) ? LatLng(_userLat!, _userLng!) : null;
    final riderPoint = (_hasRiderFix && _riderLat != null && _riderLng != null) ? LatLng(_riderLat!, _riderLng!) : null;

    return Scaffold(
      body: Column(children: [
        // ── Map + bike overlay ──────────────────────────────────────────────
        SizedBox(
          height: mapHeight,
          child: Stack(children: [
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: userPoint ?? riderPoint ?? const LatLng(28.6315, 77.2167),
                initialZoom: 15,
                onMapReady: () {
                  _mapReady = true;
                  _fitMapToPoints();
                },
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.tezdrop.app',
                ),
                if (_routePoints.length > 1)
                  PolylineLayer(polylines: [
                    Polyline(points: _routePoints, color: AppColors.primary, strokeWidth: 4),
                  ]),
                MarkerLayer(markers: [
                  if (userPoint != null)
                    Marker(
                      point: userPoint,
                      width: 32, height: 32,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.textDark, width: 2),
                          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6)],
                        ),
                        child: const Icon(Icons.home_rounded, size: 16, color: AppColors.textDark),
                      ),
                    ),
                  if (riderPoint != null)
                    Marker(
                      point: riderPoint,
                      width: 46, height: 46,
                      child: AnimatedBuilder(
                        animation: _bikeAnim,
                        builder: (_, __) => Transform.rotate(
                          angle: _bearing() * math.pi / 180,
                          child: Container(
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              shape: BoxShape.circle,
                              boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.4), blurRadius: 12, spreadRadius: 2)],
                            ),
                            child: const Center(child: Text('🛵', style: TextStyle(fontSize: 22))),
                          ),
                        ),
                      ),
                    ),
                ]),
              ],
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
            child: !_statusLoaded
                ? _bottomPanelSkeleton()
                : ListView(
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

                // Delivery OTP — customer shows this to the rider at handover
                if (_deliveryOtp.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(16),
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF7ED),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFFED7AA)),
                    ),
                    child: Column(children: [
                      const Text('Share this OTP with your rider at delivery',
                          style: TextStyle(fontSize: 12, color: AppColors.textGrey), textAlign: TextAlign.center),
                      const SizedBox(height: 8),
                      Text(
                        _deliveryOtp.split('').join('  '),
                        style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: Color(0xFFEA580C), letterSpacing: 4),
                      ),
                    ]),
                  ),
                ],
              ],
            ),
          ),
        ),
      ]),
    );
  }

  Widget _bottomPanelSkeleton() {
    Widget box(double w, double h, {double r = 8}) => Container(
      width: w, height: h,
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(r)),
    );
    return Shimmer.fromColors(
      baseColor: const Color(0xFFE5E7EB),
      highlightColor: const Color(0xFFF9FAFB),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              box(120, 18), const SizedBox(height: 8), box(90, 12),
            ]),
            box(46, 46, r: 23),
          ]),
          const SizedBox(height: 20),
          Row(children: List.generate(5, (i) => Expanded(child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Column(children: [box(28, 28, r: 14), const SizedBox(height: 6), box(40, 8)]),
          )))),
          const SizedBox(height: 20),
          box(double.infinity, 64, r: 14),
          const SizedBox(height: 12),
          box(double.infinity, 40, r: 12),
        ]),
      ),
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
