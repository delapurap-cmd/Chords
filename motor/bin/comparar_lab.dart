import 'dart:io';

import 'package:motor_acordes/motor_acordes.dart';

/// Puntúa dos carpetas de `.lab` una contra la otra y saca los números en un
/// formato que se lee fácil desde otro programa.
///
///   dart run bin/comparar_lab.dart <referencias> <estimaciones>
///
/// Lo usa `laboratorio/verificar_puntuador.py` para comprobar que este
/// puntuador y `mir_eval` dan lo mismo. También sirve suelto para puntuar la
/// salida de cualquier reconocedor, sea nuestro o no, sin tener que volver a
/// analizar el audio.
void main(List<String> argumentos) {
  if (argumentos.length != 2) {
    stderr.writeln('Uso: dart run bin/comparar_lab.dart <referencias> <estimaciones>');
    exit(1);
  }

  final carpetaRef = Directory(argumentos[0]);
  final carpetaEst = Directory(argumentos[1]);
  for (final c in [carpetaRef, carpetaEst]) {
    if (!c.existsSync()) {
      stderr.writeln('No existe la carpeta "${c.path}".');
      exit(1);
    }
  }

  final referencias = carpetaRef
      .listSync()
      .whereType<File>()
      .where((f) => f.path.toLowerCase().endsWith('.lab'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  if (referencias.isEmpty) {
    stderr.writeln('No hay ningún .lab en "${carpetaRef.path}".');
    exit(1);
  }

  final porCancion = <Map<Nivel, Puntuacion>>[];
  var comparadas = 0;

  for (final ref in referencias) {
    final nombre = ref.uri.pathSegments.last;
    final est = File('${carpetaEst.path}/$nombre');
    if (!est.existsSync()) {
      stderr.writeln('Falta la estimación de $nombre, se salta.');
      continue;
    }
    try {
      final tramosRef = leerLabDeArchivo(ref.path);
      final tramosEst = leerLabDeArchivo(est.path);
      if (tramosRef.isEmpty) continue;
      porCancion.add(evaluar(tramosRef, tramosEst));
      comparadas++;
    } catch (e) {
      stderr.writeln('$nombre: $e');
    }
  }

  if (comparadas == 0) {
    stderr.writeln('No se pudo comparar ninguna canción.');
    exit(1);
  }

  final total = agregar(porCancion);
  stderr.writeln('Comparadas $comparadas canciones.');
  for (final nivel in Nivel.values) {
    stdout.writeln('${nivel.nombre} = ${total[nivel]!.wcsr.toStringAsFixed(6)}');
  }
}
