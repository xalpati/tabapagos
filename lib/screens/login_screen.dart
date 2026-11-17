import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../database/db_helper.dart';
import '../services/api_service.dart';
import '../services/fcm_service.dart';
import 'pos_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  // 0 = Iniciar Sesión, 1 = Crear Cuenta
  int _tabIndex = 0;
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();

  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<String> _getOrCreateInstallationId() async {
    String? id = await DbHelper.instance.getSetting('installation_id');
    // Asegurar que sea un UUID v4 válido de 36 caracteres
    if (id == null || id.isEmpty || id.length != 36) {
      id = ApiService.generateUuid();
      await DbHelper.instance.setSetting('installation_id', id);
    }
    return id;
  }

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    String installationId = await _getOrCreateInstallationId();

    // Para registro nuevo de cuenta, asegurar un identificador de instalación fresco y único
    // para evitar conflictos 409 con sesiones de demostración o usuarios anteriores en el mismo hardware
    if (_tabIndex == 1) {
      installationId = ApiService.generateUuid();
      await DbHelper.instance.setSetting('installation_id', installationId);
    }

    try {
      if (_tabIndex == 0) {
        // Iniciar Sesión
        final res = await ApiService.instance.login(
          email: _emailController.text,
          password: _passwordController.text,
          installationId: installationId,
        );

        if (!mounted) return;

        if (res['success'] == true) {
          final data = res['data'];

          // Si el usuario venía de una sesión demo, limpiar datos demo locales
          final wasDemo = await DbHelper.instance.isDemoSession();
          if (wasDemo) {
            await DbHelper.instance.clearAllDataForNewUser();
          }

          await DbHelper.instance.startUserSession(
            token: data['access_token'] ?? '',
            email: data['email'] ?? _emailController.text.trim(),
            name: data['name'] ?? 'Comerciante',
            deviceId: data['device_id'] ?? installationId,
          );

          if (data['name'] != null && data['name'].toString().isNotEmpty) {
            await DbHelper.instance.setSetting('business_name', data['name']);
          }

          // Sincronizar cuenta bancaria vinculada desde la API si ya está registrada
          try {
            final bankRes = await ApiService.instance.getBankAccount();
            if (bankRes != null && bankRes['data'] != null) {
              final bankData = bankRes['data'];
              await DbHelper.instance.saveBankAccount(
                alias: bankData['alias'] ?? 'Cuenta Principal CoDi',
                holderName: bankData['holder_name'] ?? data['name'] ?? 'Tabapagos POS',
                clabe: bankData['clabe'] ?? '',
                entity: bankData['entity'] ?? 'PERSON',
                bankName: bankData['bank_name'] ?? 'Banco',
                status: bankData['status'] ?? 'ACTIVE',
              );
            }
          } catch (_) {}

          // Sincronizar token FCM con la API de Hostinger
          try {
            await FcmService.instance.syncPushToken();
          } catch (_) {}

          if (!mounted) return;

          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const PosScreen()),
          );
        } else {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: Colors.red.shade700,
              content: Text(res['message'] ?? 'Error al iniciar sesión'),
            ),
          );
        }
      } else {
        // Crear Cuenta
        final res = await ApiService.instance.register(
          name: _nameController.text,
          email: _emailController.text,
          password: _passwordController.text,
          passwordConfirmation: _confirmPasswordController.text,
          installationId: installationId,
        );

        if (!mounted) return;

        if (res['success'] == true) {
          final data = res['data'];

          // Al crear cuenta nueva, limpiar por completo cualquier dato demo o residual
          // para que el comerciante inicie 100% en blanco (catálogo, ventas, banco e impresora vacíos)
          await DbHelper.instance.clearAllDataForNewUser();

          await DbHelper.instance.startUserSession(
            token: data['access_token'] ?? '',
            email: data['email'] ?? _emailController.text.trim(),
            name: data['name'] ?? _nameController.text.trim(),
            deviceId: data['device_id'] ?? installationId,
          );

          await DbHelper.instance.setSetting('business_name', _nameController.text.trim());

          // Sincronizar token FCM con la API de Hostinger
          try {
            await FcmService.instance.syncPushToken();
          } catch (_) {}

          if (!mounted) return;

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              backgroundColor: AppTheme.primary,
              content: Text('¡Cuenta creada exitosamente! Bienvenido a Tabapagos.'),
            ),
          );

          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const PosScreen()),
          );
        } else {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: Colors.red.shade700,
              content: Text(res['message'] ?? 'Error al registrar la cuenta'),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red.shade700,
            content: Text('Error de conexión con el servidor: $e'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _startDemoMode() async {
    setState(() => _isLoading = true);

    try {
      await DbHelper.instance.startDemoSession();
      await DbHelper.instance.restoreDemoCatalog();
    } catch (_) {
      await DbHelper.instance.startDemoSession();
    }

    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const PosScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Logotipo de la Marca Tabapagos
                Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.08),
                        blurRadius: 14,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ClipOval(
                    child: Image.asset(
                      'assets/images/tabapagos_brand_logo.jpg',
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.point_of_sale,
                        size: 48,
                        color: AppTheme.primary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // Títulos de Marca
                const Text(
                  'Tabapagos POS',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Punto de Venta y Cobro Digital Mexicano',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 24),

                // Selector de modo: Iniciar Sesión vs Crear Cuenta
                Container(
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E293B) : Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  padding: const EdgeInsets.all(4),
                  child: Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: () => setState(() => _tabIndex = 0),
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: _tabIndex == 0
                                  ? (isDark ? const Color(0xFF334155) : Colors.white)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(10),
                              boxShadow: _tabIndex == 0
                                  ? [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.08),
                                        blurRadius: 4,
                                        offset: const Offset(0, 1),
                                      ),
                                    ]
                                  : null,
                            ),
                            child: Text(
                              'Iniciar Sesión',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontWeight: _tabIndex == 0 ? FontWeight.bold : FontWeight.w500,
                                color: _tabIndex == 0
                                    ? (isDark ? Colors.white : Colors.black87)
                                    : Colors.grey.shade600,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: InkWell(
                          onTap: () => setState(() => _tabIndex = 1),
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: _tabIndex == 1
                                  ? (isDark ? const Color(0xFF334155) : Colors.white)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(10),
                              boxShadow: _tabIndex == 1
                                  ? [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.08),
                                        blurRadius: 4,
                                        offset: const Offset(0, 1),
                                      ),
                                    ]
                                  : null,
                            ),
                            child: Text(
                              'Crear Cuenta',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontWeight: _tabIndex == 1 ? FontWeight.bold : FontWeight.w500,
                                color: _tabIndex == 1
                                    ? (isDark ? Colors.white : Colors.black87)
                                    : Colors.grey.shade600,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Formulario de Credenciales
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E293B) : Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.04),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_tabIndex == 1) ...[
                          TextFormField(
                            controller: _nameController,
                            textCapitalization: TextCapitalization.words,
                            decoration: const InputDecoration(
                              labelText: 'Nombre del Negocio o Titular',
                              prefixIcon: Icon(Icons.storefront_outlined),
                              border: OutlineInputBorder(),
                            ),
                            validator: (v) {
                              if (_tabIndex == 1 && (v == null || v.trim().isEmpty)) {
                                return 'Ingresa el nombre del negocio o comerciante';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                        ],

                        TextFormField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          autocorrect: false,
                          decoration: const InputDecoration(
                            labelText: 'Correo Electrónico',
                            prefixIcon: Icon(Icons.email_outlined),
                            border: OutlineInputBorder(),
                          ),
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) {
                              return 'Ingresa tu correo electrónico';
                            }
                            if (!v.contains('@') || !v.contains('.')) {
                              return 'Ingresa un correo electrónico válido';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),

                        TextFormField(
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          decoration: InputDecoration(
                            labelText: 'Contraseña',
                            prefixIcon: const Icon(Icons.lock_outline),
                            border: const OutlineInputBorder(),
                            suffixIcon: IconButton(
                              icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
                              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                            ),
                          ),
                          validator: (v) {
                            if (v == null || v.isEmpty) {
                              return 'Ingresa tu contraseña';
                            }
                            if (_tabIndex == 1 && v.length < 8) {
                              return 'La contraseña debe tener al menos 8 caracteres';
                            }
                            return null;
                          },
                        ),

                        if (_tabIndex == 1) ...[
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _confirmPasswordController,
                            obscureText: _obscureConfirmPassword,
                            decoration: InputDecoration(
                              labelText: 'Confirmar Contraseña',
                              prefixIcon: const Icon(Icons.lock_reset),
                              border: const OutlineInputBorder(),
                              suffixIcon: IconButton(
                                icon: Icon(_obscureConfirmPassword ? Icons.visibility_off : Icons.visibility),
                                onPressed: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
                              ),
                            ),
                            validator: (v) {
                              if (_tabIndex == 1 && v != _passwordController.text) {
                                return 'Las contraseñas no coinciden';
                              }
                              return null;
                            },
                          ),
                        ],

                        const SizedBox(height: 22),

                        // Botón de Enviar Formulario
                        SizedBox(
                          height: 52,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primary,
                              foregroundColor: Colors.white,
                              elevation: 2,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            onPressed: _isLoading ? null : _submitForm,
                            child: _isLoading
                                ? const SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                                  )
                                : Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(_tabIndex == 0 ? Icons.login : Icons.person_add_alt_1),
                                      const SizedBox(width: 10),
                                      Text(
                                        _tabIndex == 0 ? 'Iniciar Sesión' : 'Crear Cuenta',
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Separador
                Row(
                  children: [
                    Expanded(child: Divider(color: Colors.grey.shade300)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        'o puedes probar primero',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                        ),
                      ),
                    ),
                    Expanded(child: Divider(color: Colors.grey.shade300)),
                  ],
                ),
                const SizedBox(height: 16),

                // Botón Probar en Modo Demo (Sin Cuenta)
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: AppTheme.secondary, width: 1.5),
                      foregroundColor: AppTheme.secondary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    icon: const Icon(Icons.storefront, size: 20),
                    label: const Text(
                      'Probar en Modo Demo (Sin Cuenta)',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                    onPressed: _isLoading ? null : _startDemoMode,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
