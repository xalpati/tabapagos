<div align="center">

# 📱 Tabapagos

### Punto de venta para micronegocios en teléfonos y tabletas Android

**Flutter · Dart · Operación local · Efectivo · CoDi · Tickets Bluetooth**

</div>

> 🚧 **En desarrollo — fase de diseño.** Este repositorio está preparado para alojar la app Android. Las funciones descritas son el alcance previsto; todavía no existe una aplicación ejecutable ni una APK publicada.

## 🧭 Explorar

[Propósito](#-propósito) · [Funciones](#-funciones-previstas) · [Conectividad](#-conectividad) · [Pagos](#-cobros-codi) · [Tecnología](#-tecnología-y-responsabilidades) · [Desarrollo](#-desarrollo)

## 🎯 Propósito

Tabapagos busca simplificar las ventas de pequeños negocios desde un teléfono o una tableta Android. Cada dispositivo conserva sus productos, existencias y ventas para continuar trabajando en efectivo cuando no haya conexión.

Este repositorio **público** corresponde exclusivamente a la aplicación móvil/tableta. El backend se desarrolla en [tabapagos_api](https://github.com/xalpati/tabapagos_api).

## 🛍️ Funciones previstas

| Área | Alcance |
|---|---|
| 🔐 Acceso | Registro e inicio de sesión con Google; un usuario por dispositivo |
| 📦 Productos | Nombre, descripción, precio, existencias, tipo de venta y unidad de medida |
| ⚖️ Presentaciones | Pieza, caja y granel; cajas como productos independientes y granel con cantidades fraccionarias |
| 🛒 Venta con artículos | Selección de productos y cantidades, subtotales y total |
| 💵 Cobro directo | Monto y concepto sin seleccionar artículos; admite efectivo o CoDi |
| 📉 Inventario | Advertencia ante existencias insuficientes; continuar requiere confirmación del usuario |
| 📊 Resumen diario | Total vendido, número de ventas, desglose por medio de pago y cancelaciones |
| 🧾 Historial | Detalle de ventas y pagos de cobros originados en ese dispositivo |
| ↩️ Cancelaciones | Conservar registro y reponer una sola vez las existencias descontadas |
| 🏪 Perfil del negocio | Logo, nombre, dirección y contacto opcionales para los tickets |
| 🖨️ Impresión | Impresoras térmicas Bluetooth de 58 y 80 mm |

Los cobros directos no generan movimientos de inventario. El registro de un reembolso externo conserva importe, medio y referencia; no ejecuta una devolución bancaria automática.

## 📶 Conectividad

| Operación | Sin internet | Con internet |
|---|---|---|
| Productos e inventario locales | ✅ | ✅ |
| Ventas y cobros directos en efectivo | ✅ | ✅ |
| Consulta de información ya guardada | ✅ | ✅ |
| Tickets en impresora Bluetooth compatible | ✅ | ✅ |
| Primer acceso con Google | — | ✅ |
| Registro y activación de cuenta bancaria | — | ✅ |
| Creación de cobros CoDi y recepción de nuevos eventos | — | ✅ |

El acceso offline se habilitará después del primer inicio de sesión. Cada dispositivo mantiene información independiente, incluso al usar la misma cuenta Google en otro equipo. No se contempla sincronización comercial ni restauración del catálogo y las ventas desde la nube.

## 💳 Cobros CoDi

La integración se realizará mediante [Pey](https://pey.mx/) y el backend de Tabapagos. Cada usuario podrá registrar una cuenta bancaria; los cobros requieren conexión y estado **ACTIVE**.

| Modalidad | Experiencia prevista |
|---|---|
| QR con impresora configurada | Ticket con detalle de venta y QR |
| QR sin impresora | Código visible en pantalla para escanear |
| Solicitud push al comprador | Captura del teléfono para enviar el requerimiento de pago |

Un ticket emitido antes de la confirmación indica **pendiente de pago**. El pago se confirmará mediante webhook en el backend y un evento firmado enviado a la app, con procesamiento local una sola vez, acuse y reenvío de eventos pendientes. No se consultará periódicamente una API para verificar pagos.

La activación bancaria también llegará por evento. La consulta al abrir la app se limitará a cuentas registradas que aún no estén validadas/activas.

> 🧩 El QR fijo reutilizable está contemplado en el alcance; su asociación inequívoca con una venta sigue pendiente de diseño. QR por operación y solicitudes push requieren validación real de la integración.

## 🖨️ Tickets de 58 y 80 mm

- Ancho guardado por impresora, con selección manual cuando no pueda detectarse.
- Datos opcionales del negocio impresos solo si están configurados.
- Detalle de artículos, cantidades e importes; concepto e importe en cobro directo.
- Funcionamiento local sin depender de internet.

La compatibilidad Bluetooth y los formatos se comprobarán con equipos físicos antes de anunciar modelos soportados.

## 🧱 Tecnología y responsabilidades

| Componente | Ubicación y función |
|---|---|
| **Flutter + Dart** | Este repositorio: interfaz Android para móvil/tableta y operación comercial local |
| **Laravel + PHP + MySQL** | [tabapagos_api](https://github.com/xalpati/tabapagos_api): identidad, cuentas bancarias, cobros, webhook y eventos |
| **Vue** | Sitio público: presentación, registro previo a descarga y guía de instalación |

La persistencia local y los complementos Android se seleccionarán al preparar la base técnica. El tema visual y la versión mínima de Android siguen por definir.

## 🔒 Seguridad prevista

Las credenciales privadas de Pey permanecerán en el backend. La aplicación tendrá autorización por usuario/dispositivo, almacenamiento privado y validación de los eventos recibidos. La configuración y las claves de firma no se publicarán en el repositorio.

Estos controles forman parte del diseño; su implementación y comprobación están pendientes.

## 🛠️ Desarrollo

```bash
git clone https://github.com/xalpati/tabapagos.git
cd tabapagos
```

Actualmente el contenido versionado es la presentación del proyecto y la configuración inicial de Git. Los comandos de instalación, ejecución, pruebas y compilación se añadirán cuando exista la base Flutter y se fijen sus dependencias.

### Próximas entregas

- [ ] Base Flutter y acceso inicial con Google.
- [ ] Productos, ventas en efectivo, inventario e historial local.
- [ ] Perfil del negocio e impresión Bluetooth.
- [ ] Cuenta bancaria, CoDi y eventos confirmados por el backend.
- [ ] Validación en teléfonos/tabletas y distribución de APK firmada.

## 📥 Distribución

La APK se ofrecerá desde la landing después de guardar un formulario de datos esenciales. Se acompañará de una guía de instalación externa y actualización. El formulario de descarga es independiente de la cuenta Google dentro de la app.

**Aún no hay una APK disponible para descargar.**
