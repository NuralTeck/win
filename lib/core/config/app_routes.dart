import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../app/main_layout.dart';
import '../constants/app_constants.dart';
import '../../features/dashboard/screens/dashboard_screen.dart';
import '../../features/operations/screens/draws_screen.dart';
import '../../features/sellers/screens/agents_screen.dart';
import '../../features/bookings/screens/ticket_sales_screen.dart';
import '../../features/bookings/screens/company_forward_screen.dart';
import '../../features/analytics/screens/analytics_screen.dart';
import '../../features/settings/screens/settings_screen.dart';
import '../../features/settings/screens/price_setup_screen.dart';
import '../../features/sellers/screens/customer_setup_screen.dart';
import '../../features/settings/screens/draw_time_setup_screen.dart';
import '../../features/operations/screens/result_entry_screen.dart';
import '../../features/collectors/screens/collector_management_screen.dart';
import '../../features/auth/screens/admin_login_screen.dart';

final GlobalKey<NavigatorState> _rootNavigatorKey = GlobalKey<NavigatorState>();

class AppRouter {
  AppRouter._();

  static final GoRouter router = GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: AppConstants.routeLogin,
    routes: [
      GoRoute(
        path: AppConstants.routeLogin,
        builder: (context, state) => const AdminLoginScreen(),
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
                path: AppConstants.routeCompanyForward,
                builder: (context, state) => const CompanyForwardScreen(),
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
                path: AppConstants.routeCustomers,
                builder: (context, state) => const CustomerSetupScreen(),
              ),
              GoRoute(
                path: AppConstants.routeSellers,
                builder: (context, state) => const AgentsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppConstants.routeCollectors,
                builder: (context, state) => const CollectorManagementScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppConstants.routeAnalytics,
                builder: (context, state) => const AnalyticsScreen(),
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
