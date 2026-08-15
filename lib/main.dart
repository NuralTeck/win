import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';
import 'core/config/app_routes.dart';
import 'core/theme/app_theme.dart';
import 'core/constants/app_constants.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'core/database/database_service.dart';
import 'core/database/supabase_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load .env environment variables
  try {
    await dotenv.load(fileName: ".env");
  } catch (e) {
    debugPrint('⚠️ Could not load .env file: $e');
  }

  // Initialize Local SQLite Database & Supabase Cloud
  await DatabaseService.instance.database;
  await SupabaseService.instance.initialize();



  // Desktop Window Management Configuration
  await windowManager.ensureInitialized();
  
  const WindowOptions windowOptions = WindowOptions(
    size: Size(1440, 900),
    minimumSize: Size(AppConstants.minWindowWidth, AppConstants.minWindowHeight),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.normal,
    title: 'NagaLand TicketCore | Lottery & Ticket Management Platform',
  );
  
  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  runApp(
    const ProviderScope(
      child: OpsCoreProApp(),
    ),
  );
}

class OpsCoreProApp extends StatelessWidget {
  const OpsCoreProApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'NagaLand TicketCore',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.dark,
      routerConfig: AppRouter.router,
    );
  }
}
