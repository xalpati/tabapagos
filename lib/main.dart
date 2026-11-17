import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'config/theme.dart';
import 'database/db_helper.dart';
import 'services/printer_service.dart';
import 'services/fcm_service.dart';
import 'screens/pos_screen.dart';
import 'screens/login_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Bloquear orientación en vertical para experiencia óptima en teléfonos Android de micronegocios
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  bool hasSession = false;

  // Inicializar base de datos SQLite local
  try {
    await DbHelper.instance.database;
    hasSession = await DbHelper.instance.hasActiveSession();
  } catch (e) {
    debugPrint('Error al inicializar base de datos: $e');
  }

  // Inicializar notificaciones push Firebase FCM (ADR-002)
  try {
    await FcmService.instance.initialize();
  } catch (e) {
    debugPrint('Error al inicializar FCM en main: $e');
  }

  // Intentar autoconexión en segundo plano a la impresora "BlueTooth Printer" de 80mm
  try {
    PrinterService.instance.autoConnect();
  } catch (_) {}

  runApp(TabapagosApp(hasSession: hasSession));
}

class TabapagosApp extends StatefulWidget {
  final bool hasSession;
  const TabapagosApp({super.key, required this.hasSession});

  @override
  State<TabapagosApp> createState() => _TabapagosAppState();
}

class _TabapagosAppState extends State<TabapagosApp> {
  ThemeMode _themeMode = ThemeMode.light;

  void toggleTheme() {
    setState(() {
      _themeMode = _themeMode == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tabapagos POS',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: _themeMode,
      home: widget.hasSession ? const PosScreen() : const LoginScreen(),
    );
  }
}
