import 'dart:io';
import 'package:image/image.dart' as img;

void main() {
  final file = File('../tabapagos_website/public/images/tabapagos_brand_logo.jpg');
  if (!file.existsSync()) {
    print('No existe archivo de origen');
    return;
  }

  final bytes = file.readAsBytesSync();
  final original = img.decodeJpg(bytes);
  if (original == null) {
    print('No se pudo decodificar');
    return;
  }

  // Recortar exclusivamente el isotipo (ticket + QR + circuito) sin el texto inferior
  final markCrop = img.copyCrop(
    original,
    x: 160,
    y: 130,
    width: 704,
    height: 500,
  );

  // Crear un lienzo cuadrado blanco de 640x640 y centrar el isotipo para márgenes perfectos de icono Android
  final canvas = img.Image(width: 640, height: 640);
  img.fill(canvas, color: img.ColorRgba8(255, 255, 255, 255));

  // Redimensionar el isotipo para que quepa armoniosamente centrado con padding
  final scaledMark = img.copyResize(markCrop, width: 500);
  final dstX = (640 - scaledMark.width) ~/ 2;
  final dstY = (640 - scaledMark.height) ~/ 2;

  img.compositeImage(canvas, scaledMark, dstX: dstX, dstY: dstY);

  final sizes = {
    'mipmap-mdpi': 48,
    'mipmap-hdpi': 72,
    'mipmap-xhdpi': 96,
    'mipmap-xxhdpi': 144,
    'mipmap-xxxhdpi': 192,
  };

  for (var entry in sizes.entries) {
    final folder = entry.key;
    final size = entry.value;

    final resized = img.copyResize(
      canvas,
      width: size,
      height: size,
      interpolation: img.Interpolation.cubic,
    );

    final outPath = 'android/app/src/main/res/$folder/ic_launcher.png';
    File(outPath).writeAsBytesSync(img.encodePng(resized));
    print('Generado $outPath ($size x $size)');
  }

  // Guardar copia para previsualización
  final preview = img.copyResize(canvas, width: 256, height: 256);
  File('assets/images/app_launcher_preview.png').writeAsBytesSync(img.encodePng(preview));
  print('Previsualización generada en assets/images/app_launcher_preview.png');
}
