import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../core/widgets/side_nav_bar.dart';
import '../core/widgets/top_app_bar.dart';
import '../core/widgets/offline_alert_overlay.dart';
import '../core/services/internet_connectivity_service.dart';
import '../core/database/database_service.dart';
import '../core/theme/app_colors.dart';
import '../features/bookings/screens/ticket_sales_screen.dart';
import '../features/bookings/widgets/ai_photo_review_dialog.dart';
import '../features/bookings/services/gemini_scanner_service.dart';
import '../features/operations/widgets/floating_engine_console.dart';

class MainLayoutScreen extends ConsumerStatefulWidget {
  final StatefulNavigationShell navigationShell;

  const MainLayoutScreen({
    super.key,
    required this.navigationShell,
  });

  @override
  ConsumerState<MainLayoutScreen> createState() => _MainLayoutScreenState();
}

class _MainLayoutScreenState extends ConsumerState<MainLayoutScreen> {
  Timer? _pendingPhotoGlobalTimer;
  bool _isReviewModalOpen = false;
  bool _isSidebarVisible = true;

  @override
  void initState() {
    super.initState();
    // 🌐 Real-time Internet Connectivity Watcher
    InternetConnectivityService.instance.initialize();
    // 📸 Global WhatsApp Photo Watcher
    _checkPendingPhotosGlobal();
    _pendingPhotoGlobalTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _checkPendingPhotosGlobal();
    });
  }

  @override
  void dispose() {
    _pendingPhotoGlobalTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkPendingPhotosGlobal() async {
    if (_isReviewModalOpen || !mounted) return;
    try {
      final photos = await DatabaseService.instance.getPendingPhotoBookings();
      if (photos.isEmpty || _isReviewModalOpen || !mounted) return;

      final photo = photos.first;
      final String photoId = photo['id'] ?? '';
      final String imageBase64 = photo['imageBase64'] ?? '';
      final String buyerName = photo['buyerName'] ?? 'Walk-in Customer';
      final String drawShift = photo['drawShift'] ?? 'Dear 1 PM';
      final String drawDateStr = photo['drawDate'] ?? '';
      final String rawJson = photo['parsedTicketsJson'] ?? '[]';

      if (imageBase64.isEmpty) return;

      final imageBytes = base64Decode(imageBase64);
      final List<GeminiScannedItem> items = [];

      try {
        final List dynamicList = jsonDecode(rawJson);
        for (final d in dynamicList) {
          final tkt = d['ticketNo']?.toString() ?? '';
          final ser = d['series']?.toString() ?? '12';
          final amt = (d['amount'] as num?)?.toDouble() ?? 0.0;
          final qty = (d['quantity'] as num?)?.toInt() ?? 1;
          items.add(GeminiScannedItem(
            series: ser,
            ticketNo: tkt,
            amount: amt,
            quantity: qty,
            sellerName: buyerName,
          ));
        }
      } catch (jsonErr) {
        debugPrint('JSON parse error for pending photo: $jsonErr');
      }

      DateTime activeDate = DateTime.now();
      if (drawDateStr.isNotEmpty) {
        try {
          activeDate = DateTime.parse(drawDateStr);
        } catch (_) {}
      }

      _isReviewModalOpen = true;

      final saved = await showDialog<bool>(
        context: context,
        useRootNavigator: true,
        barrierDismissible: false,
        builder: (ctx) => AiPhotoReviewDialog(
          imageBytes: imageBytes,
          initialItems: items,
          activeShift: drawShift,
          activeDate: activeDate,
          defaultSeller: buyerName,
          pendingPhotoId: photoId,
        ),
      );

      _isReviewModalOpen = false;

      if (saved == true && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ WhatsApp Photo confirmed & numbers booked for $buyerName!'),
            backgroundColor: AppColors.success,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      _isReviewModalOpen = false;
      debugPrint('Error in global pending photo check: $e');
    }
  }

  void _openNewTicketDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withAlpha(153),
      builder: (context) => const NewTicketSaleDialog(),
    );
  }



  @override
  Widget build(BuildContext context) {
    final currentRoute = GoRouterState.of(context).uri.toString();

    return Scaffold(
      body: Stack(
        children: [
          Row(
            children: [
              // Collapsible Sidebar Navigation
              if (_isSidebarVisible)
                SideNavBar(
                  currentRoute: currentRoute,
                  onNewOperationPressed: () => _openNewTicketDialog(context),
                  navigationShell: widget.navigationShell,
                  onToggleCollapse: () => setState(() => _isSidebarVisible = false),
                ),

              // Main Workspace Area
              Expanded(
                child: Column(
                  children: [
                    TopAppBar(
                      title: 'PhantomManagement — Hisab Management Platform',
                      isSidebarVisible: _isSidebarVisible,
                      onToggleSidebar: () => setState(() => _isSidebarVisible = !_isSidebarVisible),
                    ),

                    Expanded(
                      child: Container(
                        color: Theme.of(context).scaffoldBackgroundColor,
                        child: widget.navigationShell,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          // FLOATING DRAGGABLE WHATSAPP ENGINE CONSOLE OVERLAY
          const FloatingEngineConsole(),

          // REAL-TIME NO INTERNET CONNECTION POPUP & OVERLAY
          const OfflineAlertOverlay(),
        ],
      ),
    );
  }
}
