class AppConstants {
  AppConstants._();

  static const String appName = 'NagaLand TicketCore';
  static const String appSubtitle = 'Enterprise Ticket & Lottery v2.4';

  static const double sidebarWidth = 260.0;
  static const double topHeaderHeight = 64.0;
  static const double bottomStatusBarHeight = 32.0;
  static const double minWindowWidth = 1280.0;
  static const double minWindowHeight = 800.0;

  // Route Paths
  static const String routeLogin = '/login';           // Admin / Owner Login Screen
  static const String routeDashboard = '/';
  static const String routeOperations = '/operations'; // Draws & Schemes
  static const String routeSellers = '/sellers';       // Ticket Agents
  static const String routeBookings = '/bookings';     // Ticket Bookings & Sales
  static const String routeCompanyForward = '/company-forward'; // Company Ticket Forwarding List
  static const String routePrices = '/prices';         // Universal Ticket Series & Price Setup
  static const String routeCustomers = '/customers';   // Customer & Seller Account Master
  static const String routeDrawTimes = '/draw-times';   // Master Draw Times & Shifts Setup
  static const String routeResultEntry = '/result-entry'; // Official Lottery Sambad Result Entry
  static const String routeAnalytics = '/analytics';   // Revenue & Payouts
  static const String routeCollectors = '/collectors'; // Money Collector Management & Payments
  static const String routeSettings = '/settings';     // Pricing & Series Setup
}
