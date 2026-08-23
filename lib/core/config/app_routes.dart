import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../app/main_layout.dart';
import '../constants/app_constants.dart';
import '../../features/dashboard/screens/dashboard_screen.dart';
import '../../features/operations/screens/draws_screen.dart';
import '../../features/bookings/screens/ticket_sales_screen.dart';
import '../../features/analytics/screens/analytics_screen.dart';
import '../../features/settings/screens/settings_screen.dart';
import '../../features/settings/screens/price_setup_screen.dart';
import '../../features/settings/screens/draw_time_setup_screen.dart';
import '../../features/operations/screens/result_entry_screen.dart';
import '../../features/operations/screens/generated_hisab_screen.dart';
import '../../features/auth/screens/admin_login_screen.dart';
import '../../features/auth/screens/splash_screen.dart';

final GlobalKey<NavigatorState> _rootNavigatorKey = GlobalKey<NavigatorState>();

class AppRouter {
  AppRouter._();

  static final GoRouter router = GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: AppConstants.routeSplash,
    routes: [
      GoRoute(
        path: AppConstants.routeSplash,
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: AppConstants.routeLogin,
        redirect: (context, state) => AppConstants.routeDashboard,
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return MainLayoutScreen(navigationShell: navigationShell);
        },
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppConstants.routeDashboard,
                builder: (context, state) => const DashboardScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppConstants.routeBookings,
                builder: (context, state) => const TicketSalesScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppConstants.routeResultEntry,
                builder: (context, state) => const ResultEntryScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppConstants.routeGeneratedHisab,
                builder: (context, state) => const GeneratedHisabScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppConstants.routeSettings,
                builder: (context, state) => const SettingsScreen(),
              ),
              GoRoute(
                path: AppConstants.routePrices,
                builder: (context, state) => const PriceSetupScreen(),
              ),
              GoRoute(
                path: AppConstants.routeDrawTimes,
                builder: (context, state) => const DrawTimeSetupScreen(),
              ),
              GoRoute(
                path: AppConstants.routeOperations,
                builder: (context, state) => const DrawsScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
}
