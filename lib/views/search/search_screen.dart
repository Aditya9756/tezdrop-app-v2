import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:permission_handler/permission_handler.dart';
import '../../core/constants/app_colors.dart';
import '../../core/models/product_model.dart';
import '../../core/routes/app_routes.dart';
import '../../providers/app_state_provider.dart';
import '../widgets/product_image.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _ctrl = TextEditingController();
  String _query = '';
  String _filter = 'all';
  Timer? _debounce;
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _speechAvailable = false;
  bool _isListening = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is Map && args['prefillQuery'] != null) {
        final q = args['prefillQuery'] as String;
        if (q.isNotEmpty) setState(() { _query = q; _ctrl.text = q; });
      }
    });
    _initSpeech();
  }

  Future<void> _initSpeech() async {
    try {
      _speechAvailable = await _speech.initialize(
        onStatus: (s) { if ((s == 'done' || s == 'notListening') && mounted) setState(() => _isListening = false); },
        onError:  (_) { if (mounted) setState(() => _isListening = false); },
      );
    } catch (_) { _speechAvailable = false; }
    if (mounted) setState(() {});
  }

  Future<void> _toggleListening() async {
    if (_isListening) {
      await _speech.stop();
      if (mounted) setState(() => _isListening = false);
      return;
    }

    // Step 1: Permission pehle maango
    final status = await Permission.microphone.request();
    if (!status.isGranted) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Microphone permission chahiye voice search ke liye.')),
      );
      return;
    }

    // Step 2: Speech init karo agar abhi tak nahi hua
    if (!_speechAvailable) await _initSpeech();
    if (!_speechAvailable) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Voice search is device pe available nahi hai.')),
      );
      return;
    }

    // Step 3: Listening shuru karo
    setState(() => _isListening = true);
    await _speech.listen(
      onResult: (r) {
        setState(() { _query = r.recognizedWords; _ctrl.text = r.recognizedWords; });
        if (r.finalResult) setState(() => _isListening = false);
      },
      listenFor: const Duration(seconds: 10),
      pauseFor: const Duration(seconds: 3),
    );
  }

  @override
  void dispose() { _debounce?.cancel(); _speech.stop(); _ctrl.dispose(); super.dispose(); }

  List<ProductModel> _results(AppStateProvider state) {
    if (_query.isEmpty) return [];
    final all = [...state.products, ...state.groceryItems];
    var list = all.where((p) { final q = _query.toLowerCase(); return p.name.toLowerCase().contains(q) || p.category.toLowerCase().contains(q); }).toList();
    if (_filter == 'food')    list = list.where((p) => !p.isGrocery).toList();
    if (_filter == 'grocery') list = list.where((p) => p.isGrocery).toList();
    if (_filter == 'veg')     list = list.where((p) => p.type == 'veg').toList();
    if (_filter == 'under99') list = list.where((p) => p.price < 99).toList();
    if (_filter == 'top')     list = list.where((p) => p.rating >= 4.5).toList();
    return list;
  }

  void _onQueryChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () { if (mounted) setState(() => _query = v); });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppStateProvider>();
    final results = _results(state);
    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: SafeArea(child: Column(children: [
        Container(
          color: Theme.of(context).colorScheme.surface,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(children: [
            GestureDetector(onTap: () => Navigator.maybePop(context), child: const Icon(Icons.arrow_back, size: 22)),
            const SizedBox(width: 12),
            Expanded(child: Container(
              decoration: BoxDecoration(color: const Color(0xFFF3F4F6), borderRadius: BorderRadius.circular(14)),
              child: Row(children: [
                const Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Icon(Icons.search, color: AppColors.textLight, size: 20)),
                Expanded(child: TextField(
                  controller: _ctrl,
                  // autofocus: false — fixes keyboard auto-opening on app start
                  decoration: InputDecoration(
                    hintText: _isListening ? 'Listening... 🎤' : 'Search food, groceries...',
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 13),
                  ),
                  onChanged: _onQueryChanged,
                )),
                if (_query.isNotEmpty)
                  GestureDetector(
                    onTap: () => setState(() { _query = ''; _ctrl.clear(); }),
                    child: const Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Icon(Icons.close, color: AppColors.textLight, size: 18)),
                  ),
                GestureDetector(
                  onTap: _toggleListening,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Icon(_isListening ? Icons.mic : Icons.mic_none, color: _isListening ? Colors.red : AppColors.primary, size: 22),
                  ),
                ),
              ]),
            )),
          ]),
        ),
        SizedBox(height: 44, child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          children: ['all','food','grocery','veg','under99','top'].asMap().entries.map((e) {
            final labels = ['All','🍕 Food','🛒 Grocery','🌿 Veg','Under ₹99','⭐ Top Rated'];
            final active = _filter == e.value;
            return GestureDetector(
              onTap: () => setState(() => _filter = e.value),
              child: Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(color: active ? AppColors.primary : const Color(0xFFF3F4F6), borderRadius: BorderRadius.circular(999)),
                child: Text(labels[e.key], style: TextStyle(color: active ? Colors.white : AppColors.textGrey, fontWeight: FontWeight.w700, fontSize: 11)),
              ),
            );
          }).toList(),
        )),
        const Divider(height: 1),
        Expanded(child: _query.isEmpty
          ? _PopularSearches(onTap: (v) => setState(() { _query = v; _ctrl.text = v; }))
          : results.isEmpty
            ? const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Text('🔍', style: TextStyle(fontSize: 56)), SizedBox(height: 12), Text('No results found', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)), SizedBox(height: 6), Text('Try different keywords', style: TextStyle(color: AppColors.textGrey, fontSize: 13))]))
            : _ResultsList(results: results)),
      ])),
    );
  }
}

class _PopularSearches extends StatelessWidget {
  final void Function(String) onTap;
  const _PopularSearches({required this.onTap});
  @override
  Widget build(BuildContext context) {
    const tags = ['🍕 Pizza','🍗 Biryani','🥛 Milk','🥦 Vegetables','🍔 Burger','🥚 Eggs','🌯 Rolls','🍜 Noodles'];
    return Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Popular Searches', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.textGrey, letterSpacing: 0.5)),
      const SizedBox(height: 12),
      Wrap(spacing: 8, runSpacing: 8, children: tags.map((t) => GestureDetector(
        onTap: () => onTap(t.split(' ').last),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          decoration: BoxDecoration(color: const Color(0xFFF3F4F6), borderRadius: BorderRadius.circular(999)),
          child: Text(t, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
        ),
      )).toList()),
    ]));
  }
}

class _ResultsList extends StatelessWidget {
  final List<ProductModel> results;
  const _ResultsList({required this.results});
  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: results.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final p = results[i];
        return GestureDetector(
          onTap: () => Navigator.pushNamed(context, AppRoutes.product, arguments: {'productId': p.id, 'isGrocery': p.isGrocery}),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
            child: Row(children: [
              ProductImage(image: p.image, size: 56, emojiFontSize: 28),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(p.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text('${p.category}${p.isGrocery ? " • 🛒" : ""} • ⭐ ${p.rating}', style: const TextStyle(color: AppColors.textGrey, fontSize: 11)),
                const SizedBox(height: 4),
                Text('₹${p.price.toInt()}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.primary)),
              ])),
              GestureDetector(
                onTap: p.isOutOfStock ? null : () => context.read<AppStateProvider>().addToCart(p),
                child: Container(
                  width: 32, height: 32,
                  decoration: BoxDecoration(color: p.isOutOfStock ? AppColors.border : const Color(0xFFFEE2E2), borderRadius: BorderRadius.circular(10)),
                  child: Icon(Icons.add, color: p.isOutOfStock ? AppColors.textLight : AppColors.primary, size: 18),
                ),
              ),
            ]),
          ),
        );
      },
    );
  }
}
