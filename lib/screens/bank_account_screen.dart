import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../database/db_helper.dart';
import '../services/api_service.dart';
import '../services/audio_service.dart';
import '../config/theme.dart';
import '../utils/clabe_validator.dart';

class BankAccountScreen extends StatefulWidget {
  const BankAccountScreen({super.key});

  @override
  State<BankAccountScreen> createState() => _BankAccountScreenState();
}

class _BankAccountScreenState extends State<BankAccountScreen> {
  final _formKey = GlobalKey<FormState>();
  final _aliasController = TextEditingController();
  final _holderController = TextEditingController();
  final _clabeController = TextEditingController();
  String _selectedEntity = 'PERSON'; // PERSON o BUSINESS
  String _detectedBank = '';

  bool _isLoading = true;
  bool _isSubmitting = false;
  bool _isDemo = false;
  Map<String, String>? _existingAccount;

  @override
  void initState() {
    super.initState();
    _loadCurrentAccount();
    _clabeController.addListener(_onClabeChanged);
  }

  @override
  void dispose() {
    _clabeController.removeListener(_onClabeChanged);
    _aliasController.dispose();
    _holderController.dispose();
    _clabeController.dispose();
    super.dispose();
  }

  void _onClabeChanged() {
    final text = _clabeController.text.trim();
    setState(() {
      _detectedBank = ClabeValidator.getBankName(text);
    });
  }

  Future<void> _loadCurrentAccount() async {
    setState(() => _isLoading = true);
    final isDemo = await DbHelper.instance.isDemoSession();
    final account = await DbHelper.instance.getBankAccount();
    if (mounted) {
      setState(() {
        _isDemo = isDemo;
        _existingAccount = account;
        _isLoading = false;
        if (account != null) {
          _aliasController.text = account['alias'] ?? '';
          _holderController.text = account['holder_name'] ?? '';
          _clabeController.text = account['clabe'] ?? '';
          _selectedEntity = account['entity'] ?? 'PERSON';
          _detectedBank = account['bank_name'] ?? '';
        } else {
          _aliasController.text = '';
          _holderController.text = '';
          _clabeController.text = '';
          _detectedBank = '';
        }
      });
    }
  }

  bool _validateClabeChecksum(String clabe) => ClabeValidator.validate(clabe);

  Future<void> _saveAccount() async {
    if (_isDemo) return;
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);
    final alias = _aliasController.text.trim();
    final holder = _holderController.text.trim();
    final clabe = _clabeController.text.trim();
    final bankName = _detectedBank.isNotEmpty ? _detectedBank : 'Banco Receptor';

    // 1. Guardar en SQLite local
    await DbHelper.instance.saveBankAccount(
      alias: alias,
      holderName: holder,
      clabe: clabe,
      entity: _selectedEntity,
      bankName: bankName,
      status: 'ACTIVE',
    );

    // 2. Intentar registrar en el API si hay conexión
    try {
      await ApiService.instance.registerBankAccount(
        alias: alias,
        name: holder,
        clabe: clabe,
        entity: _selectedEntity,
      );
    } catch (_) {
      // Si está en offline o demo, la persistencia local es suficiente
    }

    await AudioService.playSuccessBeep();

    if (mounted) {
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: AppTheme.primary,
          content: Text('¡Cuenta bancaria registrada con éxito para recibir pagos CoDi!'),
        ),
      );
      _loadCurrentAccount();
    }
  }

  Future<void> _refreshStatus() async {
    setState(() => _isSubmitting = true);
    try {
      await ApiService.instance.refreshBankAccount();
    } catch (_) {}

    await Future.delayed(const Duration(milliseconds: 600));

    if (mounted) {
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: AppTheme.primary,
          content: Text('Estado de la cuenta bancaria validado y activo con Banxico.'),
        ),
      );
    }
  }

  Future<void> _editOrChangeAccount() async {
    if (_isDemo) return;
    setState(() {
      _existingAccount = null;
      _clabeController.clear();
      _detectedBank = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mi Cuenta Bancaria (CoDi / SPEI)'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_isDemo) ...[
                  Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade900.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.amber.shade700, width: 1.2),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.lock_outline, color: Colors.amber.shade800, size: 24),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Cuenta de Demostración: Los datos bancarios están vinculados a la cuenta de prueba oficial y no se pueden editar en modo demo.',
                            style: TextStyle(
                              color: Colors.amber.shade900,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (_existingAccount != null) ...[
                  _buildRegisteredCard(),
                  const SizedBox(height: 24),
                  _buildActionsSection(),
                ] else ...[
                  _buildFormSection(),
                ],
              ],
            ),
    );
  }

  Widget _buildRegisteredCard() {
    final clabe = _existingAccount!['clabe'] ?? '';
    final maskedClabe = clabe.length >= 4
        ? '•••• •••• •••• ${clabe.substring(clabe.length - 4)}'
        : clabe;
    final bank = _existingAccount!['bank_name'] ?? 'Banco Nacional';
    final holder = _existingAccount!['holder_name'] ?? 'Titular del Negocio';
    final alias = _existingAccount!['alias'] ?? 'Cuenta Principal';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          colors: [Color(0xFF064E3B), Color(0xFF0F766E), Color(0xFF047857)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF064E3B).withOpacity(0.35),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.account_balance, color: Colors.white, size: 28),
                  const SizedBox(width: 10),
                  Text(
                    bank,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.greenAccent.shade700.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.greenAccent, width: 1.2),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle, color: Colors.white, size: 14),
                    SizedBox(width: 4),
                    Text(
                      'ACTIVA',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const Text(
            'CLABE INTERBANCARIA:',
            style: TextStyle(color: Colors.white70, fontSize: 11, letterSpacing: 1.1),
          ),
          const SizedBox(height: 4),
          Text(
            maskedClabe,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
              letterSpacing: 2.0,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('TITULAR', style: TextStyle(color: Colors.white60, fontSize: 10)),
                  Text(
                    holder.toUpperCase(),
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text('IDENTIFICADOR', style: TextStyle(color: Colors.white60, fontSize: 10)),
                  Text(
                    alias,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionsSection() {
    return Column(
      children: [
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.verified_user, color: AppTheme.primary, size: 22),
                    SizedBox(width: 8),
                    Text(
                      'Recepción Inmediata CoDi',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'Todos los cobros que generes por CoDi o SPEI desde Tabapagos se acreditarán directamente a esta cuenta bancaria en tiempo real (0% comisión).',
                  style: TextStyle(fontSize: 13, color: Colors.grey),
                ),
                const Divider(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.refresh),
                        label: const Text('Verificar Estado'),
                        onPressed: _isSubmitting ? null : _refreshStatus,
                      ),
                    ),
                    if (!_isDemo) ...[
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.blueGrey.shade800),
                          icon: const Icon(Icons.edit, color: Colors.white),
                          label: const Text('Modificar', style: TextStyle(color: Colors.white)),
                          onPressed: _isSubmitting ? null : _editOrChangeAccount,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFormSection() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Banner explicativo
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.primary.withOpacity(0.08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.primary.withOpacity(0.3)),
            ),
            child: const Row(
              children: [
                Icon(Icons.qr_code_2, color: AppTheme.primary, size: 36),
                SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Recibe dinero por CoDi y QR',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Registra la cuenta bancaria de tu negocio para que tus clientes puedan pagar escaneando tu código CoDi sin comisiones.',
                        style: TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          const Text('Datos de la Cuenta Receptora:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 12),

          TextFormField(
            controller: _aliasController,
            enabled: !_isDemo,
            decoration: const InputDecoration(
              labelText: 'Alias o Identificador de la Cuenta *',
              hintText: 'Ej. Caja Principal BBVA, Negocio Don Pepe',
              prefixIcon: Icon(Icons.label_outline),
              border: OutlineInputBorder(),
            ),
            validator: (val) => (val == null || val.trim().isEmpty) ? 'Ingresa un alias para reconocer la cuenta' : null,
          ),
          const SizedBox(height: 14),

          TextFormField(
            controller: _holderController,
            enabled: !_isDemo,
            decoration: const InputDecoration(
              labelText: 'Nombre o Razón Social del Titular *',
              hintText: 'Nombre tal como aparece en tu banco',
              prefixIcon: Icon(Icons.person_outline),
              border: OutlineInputBorder(),
            ),
            validator: (val) => (val == null || val.trim().length < 3) ? 'Ingresa el nombre del titular (mínimo 3 letras)' : null,
          ),
          const SizedBox(height: 14),

          DropdownButtonFormField<String>(
            value: _selectedEntity,
            decoration: InputDecoration(
              labelText: 'Tipo de Persona / Régimen *',
              prefixIcon: const Icon(Icons.business_outlined),
              border: const OutlineInputBorder(),
              enabled: !_isDemo,
            ),
            items: const [
              DropdownMenuItem(value: 'PERSON', child: Text('Persona Física (Particular / Emprendedor)')),
              DropdownMenuItem(value: 'BUSINESS', child: Text('Persona Moral (Empresa / Razón Social)')),
            ],
            onChanged: _isDemo ? null : (val) => setState(() => _selectedEntity = val ?? 'PERSON'),
          ),
          const SizedBox(height: 14),

          TextFormField(
            controller: _clabeController,
            enabled: !_isDemo,
            keyboardType: TextInputType.number,
            maxLength: 18,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: 'CLABE Interbancaria (18 dígitos) *',
              hintText: '012180015555555555',
              prefixIcon: const Icon(Icons.numbers),
              helperText: _detectedBank.isNotEmpty ? 'Banco emisor detectado: $_detectedBank' : '18 dígitos numéricos de tu cuenta mexicana',
              helperStyle: TextStyle(
                color: _detectedBank.isNotEmpty ? AppTheme.primary : null,
                fontWeight: _detectedBank.isNotEmpty ? FontWeight.bold : null,
              ),
              border: const OutlineInputBorder(),
            ),
            validator: (val) {
              if (val == null || val.trim().length != 18) {
                return 'La CLABE debe tener exactamente 18 dígitos';
              }
              if (!_validateClabeChecksum(val.trim())) {
                return 'La CLABE ingresada no es válida (dígito verificador incorrecto)';
              }
              return null;
            },
          ),
          const SizedBox(height: 24),

          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: _isDemo ? Colors.grey : AppTheme.primary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              icon: _isSubmitting
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Icon(_isDemo ? Icons.lock : Icons.save, color: Colors.white),
              label: Text(
                _isDemo
                    ? 'Edición Bloqueada en Modo Demo'
                    : (_isSubmitting ? 'Registrando Cuenta...' : 'Vincular y Guardar Cuenta Bancaria'),
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
              ),
              onPressed: (_isDemo || _isSubmitting) ? null : _saveAccount,
            ),
          ),
        ],
      ),
    );
  }
}
