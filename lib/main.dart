import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';
import 'core/config/app_routes.dart';
import 'core/theme/app_theme.dart';

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
  try {
    await DatabaseService.instance.database;
  } catch (e) {
    debugPrint('⚠️ Local SQLite initialization note: $e');
  }

  try {
    await SupabaseService.instance.initialize();
  } catch (e) {
    debugPrint('⚠️ Supabase initialization note: $e');
  }

  // Desktop Window Management Configuration (Windows / Linux / MacOS only)
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    try {
      await windowManager.ensureInitialized();

      const WindowOptions windowOptions = WindowOptions(
        size: Size(1440, 900),
        minimumSize: Size(1280, 800),
        center: true,
        backgroundColor: Color(0xFF0F172A),
        skipTaskbar: false,
        titleBarStyle: TitleBarStyle.normal,
        title: 'PhantomManagement | Operations & Hisab Management Platform',
      );

      windowManager.waitUntilReadyToShow(windowOptions, () async {
        await windowManager.show();
        await windowManager.maximize();
        await windowManager.focus();
      });
    } catch (e) {
      debugPrint('⚠️ Window manager initialization note: $e');
    }

    // Fallback direct show to guarantee window visibility on Windows desktop
    Future.microtask(() async {
      try {
        await windowManager.show();
        await windowManager.focus();
      } catch (_) {}
    });
  }

  runApp(
    const ProviderScope(
      child: TicketCoreApp(),
    ),
  );
}

class TicketCoreApp extends ConsumerWidget {
  const TicketCoreApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'PhantomManagement',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.dark,
      routerConfig: AppRouter.router,
    );
  }
}
