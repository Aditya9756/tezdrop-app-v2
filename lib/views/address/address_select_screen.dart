import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/routes/app_routes.dart';
import '../../providers/app_state_provider.dart';
import 'map_address_picker_screen.dart';

class AddressSelectScreen extends StatelessWidget {
  const AddressSelectScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppStateProvider>();
    final addrs = state.addresses;
    return Scaffold(
      appBar: AppBar(title: const Text('Select Delivery Address')),
      body: Stack(children: [
        ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
          children: [
            GestureDetector(
              onTap: () async {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('GPS se location fetch ho rahi hai... ⏳'),
                  backgroundColor: AppColors.green,
                  duration: Duration(seconds: 2),
                ));
                await state.fetchCurrentLocation();
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).clearSnackBars();
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text('Location set: \${state.currentAddress} 📍'),
                  backgroundColor: AppColors.green,
                  behavior: SnackBarBehavior.floating,
                ));
              },
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0FDF4),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFBBF7D0)),
                ),
                child: Row(children: [
                  Container(
                    width: 40, height: 40,
                    decoration: const BoxDecoration(
                        color: AppColors.green, shape: BoxShape.circle),
                    child: const Icon(Icons.my_location,
                        color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Use My Current Location',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: Color(0xFF15803D))),
                        Text(
                          state.liveLocationActive
                              ? state.currentAddress
                              : 'Tap to fetch your GPS location',
                          style: const TextStyle(
                              fontSize: 11, color: Color(0xFF16A34A)),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.gps_fixed,
                      color: AppColors.green, size: 22),
                ]),
              ),
            ),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const MapAddressPickerScreen()),
              ),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(children: [
                  Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.1), shape: BoxShape.circle),
                    child: const Icon(Icons.map_outlined, color: AppColors.primary, size: 20),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Set Location on Map',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        Text('Pin-point your exact address',
                            style: TextStyle(fontSize: 11, color: AppColors.textGrey)),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: AppColors.textLight),
                ]),
              ),
            ),
            const SizedBox(height: 16),
            if (addrs.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Text('No addresses. Add one below.',
                      style: TextStyle(color: AppColors.textGrey)),
                ),
              )
            else
              ...addrs.asMap().entries.map((entry) {
                final i = entry.key;
                final a = entry.value;
                final isSelected = state.selectedAddress == a;
                return GestureDetector(
                  onTap: () => state.selectAddress(i),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                          color: isSelected
                              ? AppColors.primary
                              : AppColors.border,
                          width: isSelected ? 2 : 1),
                    ),
                    child: Row(children: [
                      Radio<int>(
                        value: i,
                        groupValue:
                            addrs.indexOf(state.selectedAddress ?? addrs.last),
                        fillColor: WidgetStateProperty.resolveWith<Color>((states) {
                          if (states.contains(WidgetState.selected)) return AppColors.primary;
                          return AppColors.textGrey;
                        }),
                        onChanged: (_) => state.selectAddress(i),
                      ),
                      Icon(
                        a.type == 'work'
                            ? Icons.work_outline
                            : a.type == 'other'
                                ? Icons.location_on_outlined
                                : Icons.home_outlined,
                        color: AppColors.primary,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              a.type[0].toUpperCase() + a.type.substring(1),
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                            const SizedBox(height: 2),
                            Text(a.displayString,
                                style: const TextStyle(
                                    color: AppColors.textGrey, fontSize: 12),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis),
                          ],
                        ),
                      ),
                    ]),
                  ),
                );
              }),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () =>
                  Navigator.pushNamed(context, AppRoutes.addAddress),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.primary, width: 2),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add, color: AppColors.primary),
                    SizedBox(width: 8),
                    Text('Add New Address',
                        style: TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),
          ],
        ),
        Positioned(
          bottom: 0, left: 0, right: 0,
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
            color: Theme.of(context).colorScheme.surface,
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  final bool hasAddress = state.selectedAddress != null || state.liveLocationActive;
                  if (!hasAddress) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('Pehle address select karo ya GPS use karo! 📍'),
                      backgroundColor: AppColors.primary,
                      behavior: SnackBarBehavior.floating,
                    ));
                    return;
                  }
                  if (state.cart.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('Pehle kuch items cart mein dalo! 🛒'),
                      backgroundColor: AppColors.primary,
                      behavior: SnackBarBehavior.floating,
                    ));
                    return;
                  }
                  Navigator.pushNamed(context, AppRoutes.payment);
                },
                child: const Text('Proceed to Payment'),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}
