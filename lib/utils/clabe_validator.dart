class ClabeValidator {
  static const Map<String, String> bankDirectory = {
    '002': 'Citibanamex',
    '012': 'BBVA México',
    '014': 'Santander México',
    '021': 'HSBC México',
    '030': 'Banco del Bajío',
    '036': 'Inbursa',
    '044': 'Scotiabank',
    '058': 'Banregio',
    '072': 'Banorte',
    '127': 'Banco Azteca',
    '138': 'BanCoppel',
    '638': 'STP (Sistema de Transferencias y Pagos)',
    '646': 'STP',
    '659': 'Spin by Oxxo',
    '684': 'Nu México',
    '689': 'Mercado Pago Wallet',
  };

  /// Valida el algoritmo de dígito verificador oficial de Banxico / ABM para CLABE de 18 dígitos.
  static bool validate(String clabe) {
    if (clabe.length != 18 || !RegExp(r'^\d{18}$').hasMatch(clabe)) {
      return false;
    }
    
    // Pesos ABM: 3, 7, 1 repetidos
    const weights = [3, 7, 1, 3, 7, 1, 3, 7, 1, 3, 7, 1, 3, 7, 1, 3, 7];
    int sum = 0;
    for (int i = 0; i < 17; i++) {
      final digit = int.parse(clabe[i]);
      sum += (digit * weights[i]) % 10;
    }
    
    final checkDigit = (10 - (sum % 10)) % 10;
    return checkDigit == int.parse(clabe[17]);
  }

  /// Identifica el banco a partir de los 3 primeros dígitos de la CLABE.
  static String getBankName(String clabe) {
    if (clabe.length < 3) return '';
    final code = clabe.substring(0, 3);
    return bankDirectory[code] ?? 'Banco Nacional ($code)';
  }
}
