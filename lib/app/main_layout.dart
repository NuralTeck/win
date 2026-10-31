import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../core/widgets/side_nav_bar.dart';
import '../core/widgets/top_app_bar.dart';
import '../core/widgets/offline_alert_overlay.dart';
import '../core/services/internet_connectivity_service.dart';
import '../core/services/pending_photos_service.dart';
import '../features/bookings/screens/ticket_sales_screen.dart';
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
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  bool _isSidebarVisible = true;

  @override
  void initState() {
    super.initState();
    // 🌐 Real-time Internet Connectivity Watcher
    InternetConnectivityService.instance.initialize();
    // 📸 Pending Photos Count Watcher (Quiet, non-disruptive)
    PendingPhotosService.instance.initialize();
  }

  @override
  void dispose() {
    PendingPhotosService.instance.dispose();
    super.dispose();
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
    final isMobile = MediaQuery.of(context).size.width < 800;

    return Scaffold(
      key: _scaffoldKey,
      drawer: isMobile
          ? Drawer(
              backgroundColor: const Color(0xFF0F172A),
              child: SideNavBar(
                currentRoute: currentRoute,
                onNewOperationPressed: () {
                  Navigator.of(context).pop();
                  _openNewTicketDialog(context);
                },
                navigationShell: widget.navigationShell,
                onToggleCollapse: () => Navigator.of(context).pop(),
              ),
            )
          : null,
      body: Stack(
        children: [
          Row(
            children: [
              // Collapsible Sidebar Navigation (Desktop only)
              if (!isMobile && _isSidebarVisible)
                RepaintBoundary(
                  child: SideNavBar(
                    currentRoute: currentRoute,
                    onNewOperationPressed: () => _openNewTicketDialog(context),
                    navigationShell: widget.navigationShell,
                    onToggleCollapse: () => setState(() => _isSidebarVisible = false),
                  ),
                ),

              // Main Workspace Area
              Expanded(
                child: Column(
                  children: [
                    RepaintBoundary(
                      child: TopAppBar(
                        title: isMobile ? 'PhantomManagement' : 'PhantomManagement — Hisab Management Platform',
                        isSidebarVisible: isMobile ? false : _isSidebarVisible,
                        onToggleSidebar: () {
                          if (isMobile) {
                            _scaffoldKey.currentState?.openDrawer();
                          } else {
                            setState(() => _isSidebarVisible = !_isSidebarVisible);
                          }
                        },
                      ),
                    ),

                    Expanded(
                      child: RepaintBoundary(
                        child: Container(
                          color: Theme.of(context).scaffoldBackgroundColor,
                          child: widget.navigationShell,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          // FLOATING DRAGGABLE WHATSAPP ENGINE CONSOLE OVERLAY (Desktop only)
          if (!isMobile) const FloatingEngineConsole(),

          // REAL-TIME NO INTERNET CONNECTION POPUP & OVERLAY
          const OfflineAlertOverlay(),
        ],
      ),
    );
  }
}
