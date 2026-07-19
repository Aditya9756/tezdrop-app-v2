import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';

class OrderLoaderScreen extends StatelessWidget {
  const OrderLoaderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Block the Android back button completely while the order is being
      // placed — backing out here left the placeOrder() call running in
      // the background, which could later navigate forward unexpectedly
      // or let the user re-tap "Confirm Order" and place a duplicate order
      // (with duplicate coin deduction/award).
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 72,
                height: 72,
                child: CircularProgressIndicator(
                  strokeWidth: 5,
                  valueColor: AlwaysStoppedAnimation<Color>(
                      AppColors.primary),
                ),
              ),
              const SizedBox(height: 28),
              const Text('Placing Order...',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 22)),
              const SizedBox(height: 10),
              Text(
                "Please wait, don't close the app",
                style: TextStyle(color: AppColors.textGrey, fontSize: 14),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
