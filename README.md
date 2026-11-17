<div align="center">

# 📱 Tabapagos POS

### Punto de venta para micronegocios en teléfonos y tabletas Android

**Flutter · Dart · SQLite local · Efectivo · CoDi Banxico · Impresión Bluetooth**

</div>

> ✅ **Aplicación funcional en producción.** Punto de venta móvil autónomo con gestión de catálogo e inventario local, escáner nativo de códigos de barras, cobros en efectivo con cálculo de cambio, cobros digitales CoDi (QR dinámico y notificación push celular) conectados con Pey/Banxico, confirmación instantánea por Firebase Cloud Messaging (FCM) e impresión de tickets térmicos Bluetooth de 58 mm y 80 mm con autocorte.

## 🧭 Explorar

[Propósito](#-propósito) · [Backend API](#-backend-api) · [Funcionalidades Implementadas](#-funcionalidades-implementadas) · [Conectividad](#-conectividad) · [Cobros CoDi](#-cobros-codi-banxico) · [Impresión Térmica](#-impresión-térmica-bluetooth) · [Arquitectura y Tecnología](#-arquitectura-y-tecnología) · [Instalación y Compilación](#-instalación-y-compilación)

## 🎯 Propósito

Tabapagos simplifica la operación diaria de comercios y emprendedores desde un teléfono o tableta Android. Cada dispositivo almacena de forma autónoma su catálogo de productos, existencias, ventas y configuración en SQLite local para operar en efectivo sin depender de internet, e integra pagos digitales interbancarios CoDi en tiempo real cuando cuenta con conexión.

## ⚙️ Backend API

El servicio de identidad, registro bancario CLABE, emisión de cobros CoDi, recepción de webhooks y despacho de eventos push firmados se encuentra en su propio repositorio público:

- **Repositorio Backend API**: [https://github.com/xalpati/tabapagos_api](https://github.com/xalpati/tabapagos_api)

## 🛍️ Funcionalidades implementadas

| Módulo | Características aplicadas |
|---|---|
| 🔐 **Autenticación y Sesiones** | Registro e inicio de sesión por correo electrónico y contraseña con tokens por instalación (`installation_id`). Incluye modo demostración aislado para pruebas rápidas y limpieza automática de datos al crear una cuenta nueva. |
| 📦 **Catálogo e Inventario** | Alta, edición y baja de productos con código de barras, categoría, precio e inventario local en SQLite. Búsqueda instantánea y filtrado por categorías. |
| 📷 **Escáner de Códigos** | Lector nativo por cámara (`mobile_scanner`) para agregar artículos al carrito al instante o buscar productos por código de barras. |
| 🛒 **Punto de Venta (POS)** | Dos modos de operación en pantalla principal: **Catálogo** (selección de productos, control de cantidades y carrito) y **Cobro Directo** (teclado numérico para monto libre y concepto sin afectar inventario). |
| 💵 **Cobro en Efectivo** | Cálculo automático de cambio, botones de denominación rápida ($20, $50, $100, $200, $500) y botón de pago exacto. |
| 📲 **Cobro CoDi QR y Push** | Generación de código QR dinámico oficial de Banxico por venta (`CODI_QR`) y envío de solicitud de cobro por notificación push al número celular del comprador a 10 dígitos (`CODI_PUSH`). |
| 🔔 **Confirmación Push FCM** | Recepción en tiempo real (primer y segundo plano) de eventos JWS firmados (`payment.received`) vía Firebase Cloud Messaging, con alerta sonora automática, cierre de venta, impresión de ticket y envío de acuse (`ACK`). |
| 🏦 **Cuenta Bancaria CLABE** | Pantalla de vinculación bancaria con validación de dígito verificador CLABE (18 dígitos), detección automática de institución bancaria y consulta de estado de activación (`PENDING` / `ACTIVE`). |
| 🧾 **Historial y Corte de Caja** | Registro detallado de ventas del dispositivo con folio, fecha/hora, método de pago (`EFECTIVO`, `CODI`, `CODI_PUSH`), referencia de transacción, desglose de artículos y reimpresión de tickets. |
| 🏪 **Perfil del Negocio** | Configuración local del nombre del comercio, RFC/identificador, dirección, teléfono y mensaje de pie de ticket, además de selector de tema claro/oscuro. |
| 🖨️ **Impresora Bluetooth** | Escaneo, emparejamiento, reconexión automática en segundo plano e impresión ESC/POS en impresoras térmicas Bluetooth de **58 mm y 80 mm** con soporte de código QR nativo y pulso de autocorte. |

## 📶 Conectividad

| Operación | Sin internet | Con internet |
|---|---|---|
| Catálogo, precios y control de inventario local | ✅ | ✅ |
| Ventas de catálogo y cobros directos en efectivo | ✅ | ✅ |
| Historial de ventas y corte de caja local | ✅ | ✅ |
| Impresión y reimpresión de tickets por Bluetooth | ✅ | ✅ |
| Registro e inicio de sesión del comerciante | — | ✅ |
| Vinculación y validación de cuenta bancaria CLABE | — | ✅ |
| Emisión de cobros CoDi (QR / Push) y confirmación FCM | — | ✅ |

Cada dispositivo conserva su propia base de datos comercial independiente. El backend no replica el catálogo ni el detalle de ventas en efectivo.

## 💳 Cobros CoDi Banxico

La integración se realiza a través de [tabapagos_api](https://github.com/xalpati/tabapagos_api) y [Pey](https://pey.mx/):

1. **CoDi QR Dinámico (`CODI_QR`)**: Genera e ilustra en pantalla el código QR oficial de Banxico con el monto exacto de la venta para que el cliente lo escanee desde su banca móvil.
2. **CoDi Notificación Push (`CODI_PUSH`)**: Solicita el número telefónico de 10 dígitos del cliente y envía el requerimiento de cobro directamente a su aplicación bancaria registrada en CoDi.
3. **Confirmación sin Polling**: En cuanto el cliente autoriza la transferencia en su banco, el webhook del proveedor notifica al backend y este envía un evento push firmado con RS256 a la app mediante Firebase Cloud Messaging. La aplicación valida el sobre JWS, reproduce el sonido de confirmación, registra la venta como pagada, imprime el comprobante y responde con el acuse durable (`APPLIED`).

## 🖨️ Impresión térmica Bluetooth

- Conexión directa mediante perfil Bluetooth Serial (SPP) con reconexión automática al iniciar la aplicación.
- Soporte configurable para rollos térmicos de **80 mm** (48 columnas) y **58 mm** (32 columnas).
- Comandos nativos ESC/POS para encabezado del negocio, tabla de artículos, totales, efectivo recibido, cambio, folio de venta, referencia CoDi y comando de corte automático de papel (`GS V`).
- Prueba de impresión integrada en el panel de configuración de impresora.

## 🧱 Arquitectura y tecnología

```text
lib/
├── config/          # Constantes de entorno y temas visuales (claro/oscuro)
├── database/        # Persistencia local SQLite (productos, ventas, ajustes, sesión)
├── models/          # Modelos de datos (Product, Sale, SaleItem, BusinessProfile)
├── screens/         # Pantallas: POS, Cobro Modal, Login, Productos, Historial, Banco, Impresora, Ajustes
├── services/        # Servicios: ApiService, FcmService, PrinterService, AudioService
└── utils/           # Utilidades y validador algorítmico de CLABE interbancaria
```

| Componente | Tecnología |
|---|---|
| Framework UI | Flutter 3 / Material 3 |
| Lenguaje | Dart 3 |
| Base de datos local | SQLite (`sqflite`) |
| Mensajería Push | `firebase_core`, `firebase_messaging` (FCM HTTP v1) |
| Escáner de cámara | `mobile_scanner` |
| Renderizado QR | `qr_flutter` |
| Impresión Bluetooth | `print_bluetooth_thermal` (ESC/POS 58 mm / 80 mm) |
| Backend remoto | [tabapagos_api](https://github.com/xalpati/tabapagos_api) (Laravel 13 · PHP · MySQL) |

## 🛠️ Instalación y compilación

```bash
git clone https://github.com/xalpati/tabapagos.git
cd tabapagos
```

Instalar dependencias y ejecutar en un dispositivo Android conectado:

```powershell
flutter pub get
flutter analyze
flutter test
flutter run
```

Generar el artefacto APK de producción firmado:

```powershell
flutter build apk --release
```

El archivo resultante se genera en `build/app/outputs/flutter-apk/app-release.apk`. Requires Android 7.0 (API 24) o superior.
