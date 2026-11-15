import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'config/theme.dart';
import 'database/db_helper.dart';
import 'services/printer_service.dart';
import 'screens/pos_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Bloquear orientación en vertical para experiencia óptima en teléfonos Android de micronegocios
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Inicializar base de datos SQLite local
  try {
    await DbHelper.instance.database;
  } catch (e) {
    debugPrint('Error al inicializar base de datos: $e');
  }

  // Intentar autoconexión en segundo plano a la impresora "BlueTooth Printer" de 80mm
  try {
    PrinterService.instance.autoConnect();
  } catch (_) {}

  runApp(const TabapagosApp());
}

class TabapagosApp extends StatefulWidget {
  const TabapagosApp({super.key});

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
      home: const PosScreen(),
    );
  }
}
