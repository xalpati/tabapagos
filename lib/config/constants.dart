class AppConstants {
  static const String appName = 'Tabapagos POS';
  static const String appVersion = '1.0.0';
  
  // URL de API en la nube (Hostinger)
  static const String productionApiUrl = 'https://tabapagos.xalpati.com/api';
  
  // Claves de API externas inyectables por entorno o delegadas al backend seguro
  static const String defaultPeyApiKey = String.fromEnvironment('PEY_API_KEY', defaultValue: '');
  static const String peyWebhookSecret = String.fromEnvironment('PEY_WEBHOOK_SECRET', defaultValue: '');
  
  // Nombre por defecto de la impresora vinculada
  static const String defaultPrinterName = 'BlueTooth Printer';
  static const String defaultPrinterMac = '66:32:5F:CD:7D:22';
  
  // Parámetros de impresión térmica
  static const int paperWidthMm = 80;
  static const int maxCharsPerLine = 48; // Estándar para 80mm font A
}
