import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
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

class _OrderTrackingScreenState extends State<OrderTrackingScreen> {
  final MapController _mapController = MapController();

  // ── Rider info — kept live via polling so name/phone appear as soon as
  // a rider accepts, even if this screen was already open.
  late String _riderName;
  late String _riderPhone;

  // ── Locations ────────────────────────────────────────────────────────────
  LatLng? _userPos;
  LatLng? _riderPos;
  List<LatLng> _routePoints = [];
  double _bikeBearing = 0;
  bool _hasRiderFix = false;
  bool _mapReady = false;

  // ── Order status ─────────────────────────────────────────────────────────
  String _orderStatus = 'Placed';
  static const List<String> _statusOrder = ['Placed', 'Preparing', 'Packed', 'On Way', 'Delivered'];

  // ── Pollers ───────────────────────────────────────────────────────────────
  Timer? _statusTimer;
  Timer? _riderTimer;

  @override
  void initState() {
    super.initState();
    _riderName = widget.riderName;
    _riderPhone = widget.riderPhone;
    _loadUserLocation();
    _startPolling();
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    _riderTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadUserLocation() async {
    final pos = await LocationService.getCurrentPosition();
    if (pos != null && mounted) {
      setState(() {
        _userPos = LatLng(pos.latitude, pos.longitude);
        _mapReady = true;
      });
    } else if (mounted) {
      setState(() => _mapReady = true);
    }
  }

  void _startPolling() {
    _pollStatus();
    _pollRider();
    _statusTimer = Timer.periodic(const Duration(seconds: 5), (_) => _pollStatus());
    _riderTimer = Timer.periodic(const Duration(seconds: 4), (_) => _pollRider());
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

    final newPos = LatLng(lat, lng);
    if (_riderPos != null) {
      setState(() => _bikeBearing = RoadRouteService.getBearing(_riderPos!, newPos));
    }
    setState(() {
      _riderPos = newPos;
      _hasRiderFix = true;
    });

    // Recompute the road route whenever we have both fixes
    if (_userPos != null) {
      final path = await RoadRouteService.getRoadPath(newPos, _userPos!);
      if (mounted) setState(() => _routePoints = path);
    }

    _fitBounds();
  }

  void _fitBounds() {
    final points = [if (_userPos != null) _userPos!, if (_riderPos != null) _riderPos!];
    if (points.length < 2) return;
    final bounds = LatLngBounds.fromPoints(points);
    _mapController.fitCamera(CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(50)));
  }

  Future<void> _call(String phone) async {
    if (phone.isEmpty) return;
    try {
      await launchUrl(Uri.parse('tel:$phone'), mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  IconData _iconFor(String step) {
    switch (step) {
      case 'Placed': return Icons.check;
      case 'Preparing': return Icons.local_fire_department;
      case 'Packed': return Icons.inventory_2;
      case 'On Way': return Icons.motorcycle;
      case 'Delivered': return Icons.home;
      default: return Icons.circle;
    }
  }

  @override
  Widget build(BuildContext context) {
    final mapHeight = MediaQuery.of(context).size.height * 0.42;

    return Scaffold(
      body: Column(
        children: [
          SizedBox(
            height: mapHeight,
            child: Stack(
              children: [
                if (!_mapReady)
                  Container(color: AppColors.border, child: const Center(child: CircularProgressIndicator()))
                else
                  FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: _userPos ?? _riderPos ?? const LatLng(28.6315, 77.2167),
                      initialZoom: 14,
                    ),
                    children: [
                      TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.tezdrop.app'),
                      if (_routePoints.length > 1)
                        PolylineLayer(polylines: [Polyline(points: _routePoints, color: AppColors.primary, strokeWidth: 4)]),
                      MarkerLayer(markers: [
                        if (_userPos != null)
                          Marker(point: _userPos!, width: 32, height: 40, child: const Icon(Icons.location_pin, color: AppColors.blue, size: 36)),
                        if (_riderPos != null)
                          Marker(point: _riderPos!, width: 44, height: 44, child: Transform.rotate(
                            angle: _bikeBearing * math.pi / 180,
                            child: Container(
                              decoration: BoxDecoration(color: AppColors.primary, shape: BoxShape.circle, boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.4), blurRadius: 10, spreadRadius: 2)]),
                              child: const Center(child: Text('🛵', style: TextStyle(fontSize: 22))),
                            ),
                          )),
                      ]),
                    ],
                  ),

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

                Positioned(
                  top: MediaQuery.of(context).padding.top + 8, left: 12,
                  child: GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 38, height: 38,
                      decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 8)]),
                      child: const Icon(Icons.arrow_back, size: 20),
                    ),
                  ),
                ),

                Positioned(
                  top: MediaQuery.of(context).padding.top + 8, right: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(color: _hasRiderFix ? AppColors.green : AppColors.textLight, borderRadius: BorderRadius.circular(999)),
                    child: Text(_hasRiderFix ? '🟢 LIVE' : 'CONNECTING...', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
                  ),
                ),
              ],
            ),
          ),

          Expanded(
            child: Container(
              color: Theme.of(context).colorScheme.surface,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(_orderStatus, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.primary)),
                        Text('Order #${widget.orderId}', style: const TextStyle(fontSize: 12, color: AppColors.textGrey)),
                      ]),
                      Container(
                        width: 46, height: 46,
                        decoration: BoxDecoration(color: const Color(0xFFF0FDF4), shape: BoxShape.circle, border: Border.all(color: const Color(0xFFBBF7D0), width: 2)),
                        child: const Icon(Icons.motorcycle, color: AppColors.green, size: 22),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  Row(
                    children: _statusOrder.asMap().entries.map((e) {
                      final i = e.key;
                      final step = e.value;
                      final done = _statusOrder.indexOf(step) < _statusOrder.indexOf(_orderStatus);
                      final active = step == _orderStatus;
                      return Expanded(child: Row(children: [
                        Expanded(child: Column(children: [
                          Container(
                            width: 28, height: 28,
                            decoration: BoxDecoration(color: done ? AppColors.green : active ? AppColors.primary : AppColors.border, shape: BoxShape.circle),
                            child: Icon(_iconFor(step), color: (done || active) ? Colors.white : AppColors.textLight, size: 13),
                          ),
                          const SizedBox(height: 3),
                          Text(step, style: TextStyle(fontSize: 7, fontWeight: FontWeight.bold, color: done ? AppColors.green : active ? AppColors.primary : AppColors.textLight), textAlign: TextAlign.center),
                        ])),
                        if (i < _statusOrder.length - 1)
                          Expanded(child: Container(height: 2, margin: const EdgeInsets.only(bottom: 16), color: done ? AppColors.green : AppColors.border)),
                      ]));
                    }).toList(),
                  ),
                  const SizedBox(height: 16),

                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: const Color(0xFFF9FAFB), borderRadius: BorderRadius.circular(14)),
                    child: Row(children: [
                      const CircleAvatar(backgroundColor: AppColors.border, child: Text('🧑')),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(_riderName.isEmpty ? 'Assigning rider...' : _riderName, style: const TextStyle(fontWeight: FontWeight.bold)),
                        const Text('⭐ Delivery Partner', style: TextStyle(fontSize: 11, color: AppColors.textGrey)),
                      ])),
                      if (_riderPhone.isNotEmpty)
                        GestureDetector(
                          onTap: () => _call(_riderPhone),
                          child: Container(
                            width: 40, height: 40,
                            decoration: const BoxDecoration(color: Color(0xFFF0FDF4), shape: BoxShape.circle),
                            child: const Icon(Icons.phone, color: AppColors.green, size: 18),
                          ),
                        ),
                    ]),
                  ),

                  const SizedBox(height: 12),

                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: const Color(0xFFEFF6FF), borderRadius: BorderRadius.circular(12)),
                    child: Row(children: [
                      const Icon(Icons.location_on, color: AppColors.primary, size: 14),
                      const SizedBox(width: 6),
                      Expanded(child: Text(
                        _hasRiderFix && _riderPos != null
                            ? 'Rider live • ${_riderPos!.latitude.toStringAsFixed(4)}, ${_riderPos!.longitude.toStringAsFixed(4)}'
                            : 'Waiting for rider GPS...',
                        style: const TextStyle(fontSize: 11, color: AppColors.primary),
                      )),
                    ]),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
