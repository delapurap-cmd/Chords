import 'dart:io';

import 'package:motor_acordes/motor_acordes.dart';

/// Banco de pruebas: corre el motor contra el corpus y saca la tabla de notas.
///
///   dart run bin/evaluar.dart ../corpus
///   dart run bin/evaluar.dart ../corpus --permanencia 0.98 --temperatura 0.05
///   dart run bin/evaluar.dart ../corpus --guardar salidas/
///
/// El corpus es una carpeta con parejas `cancion.wav` y `cancion.lab`.
void main(List<String> argumentos) {
  if (argumentos.isEmpty || argumentos.contains('--ayuda') || argumentos.contains('-h')) {
    _ayuda();
    exit(argumentos.isEmpty ? 1 : 0);
  }

  final carpeta = Directory(argumentos.first);
  if (!carpeta.existsSync()) {
    stderr.writeln('No existe la carpeta "${argumentos.first}".');
    exit(1);
  }

  final permanencia = _leerDouble(argumentos, '--permanencia') ?? 0.96;
  final temperatura = _leerDouble(argumentos, '--temperatura') ?? 0.08;
  final umbral = _leerDouble(argumentos, '--umbral-silencio') ?? 0.015;
  final guardarEn = _leerTexto(argumentos, '--guardar');

  final motor = MotorV0(
    ajustes: AjustesDelMotor(
      permanencia: permanencia,
      temperatura: temperatura,
      umbralDeSilencio: umbral,
    ),
  );

  final wavs = carpeta
      .listSync()
      .whereType<File>()
      .where((f) => f.path.toLowerCase().endsWith('.wav'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  if (wavs.isEmpty) {
    stderr.writeln('No hay ningún .wav en "${carpeta.path}".');
    stderr.writeln('El corpus son parejas cancion.wav + cancion.lab.');
    exit(1);
  }

  stdout.writeln('Motor v0  ·  permanencia $permanencia  ·  temperatura $temperatura');
  stdout.writeln('');

  final porCancion = <Map<Nivel, Puntuacion>>[];
  final confusiones = Confusiones();
  var analizadas = 0;
  var sinEtiquetas = 0;

  for (final wav in wavs) {
    final base = wav.path.substring(0, wav.path.length - 4);
    final lab = File('$base.lab');
    final nombre = wav.uri.pathSegments.last;

    if (!lab.existsSync()) {
      stdout.writeln('  $nombre → sin .lab, no se puede puntuar');
      sinEtiquetas++;
      continue;
    }

    final cronometro = Stopwatch()..start();
    final List<Tramo> estimado;
    try {
      estimado = motor.analizarArchivo(wav.path);
    } catch (e) {
      stdout.writeln('  $nombre → error al analizar: $e');
      continue;
    }
    cronometro.stop();

    final List<Tramo> referencia;
    try {
      referencia = leerLabDeArchivo(lab.path);
    } catch (e) {
      stdout.writeln('  $nombre → el .lab está mal: $e');
      continue;
    }
    if (referencia.isEmpty) {
      stdout.writeln('  $nombre → el .lab está vacío');
      continue;
    }

    final nota = evaluar(referencia, estimado, confusiones: confusiones);
    porCancion.add(nota);
    analizadas++;

    final duracion = referencia.last.fin - referencia.first.inicio;
    final velocidad = duracion / (cronometro.elapsedMilliseconds / 1000.0);
    stdout.writeln('  ${nombre.padRight(34)}'
        ' fund ${_pct(nota[Nivel.fundamental]!.wcsr)}'
        '  may/men ${_pct(nota[Nivel.mayorMenor]!.wcsr)}'
        '  7as ${_pct(nota[Nivel.septimas]!.wcsr)}'
        '  (${velocidad.toStringAsFixed(0)}× tiempo real)');

    if (guardarEn != null) {
      Directory(guardarEn).createSync(recursive: true);
      final salida = File('$guardarEn/${nombre.substring(0, nombre.length - 4)}.lab');
      salida.writeAsStringSync(escribirLab(estimado));
    }
  }

  if (analizadas == 0) {
    stderr.writeln('\nNo se pudo puntuar ninguna canción.');
    exit(1);
  }

  final total = agregar(porCancion);
  stdout.writeln('');
  stdout.writeln('─' * 62);
  stdout.writeln('TOTAL sobre $analizadas ${analizadas == 1 ? "canción" : "canciones"}'
      '${sinEtiquetas > 0 ? "  ($sinEtiquetas sin .lab)" : ""}');
  stdout.writeln('─' * 62);
  stdout.writeln('  ${"nivel".padRight(22)}${"WCSR".padLeft(8)}${"cobertura".padLeft(12)}');
  for (final nivel in Nivel.values) {
    final p = total[nivel]!;
    stdout.writeln('  ${nivel.nombre.padRight(22)}'
        '${_pct(p.wcsr).padLeft(8)}'
        '${_pct(p.cobertura).padLeft(12)}');
  }

  stdout.writeln('');
  stdout.writeln('La cobertura dice qué parte del corpus entra en cada nivel.');
  stdout.writeln('Si es baja, esa nota se apoya en poco tiempo: míratela con recelo.');

  final peores = confusiones.peores(12);
  if (peores.isNotEmpty) {
    stdout.writeln('');
    stdout.writeln('Confusiones más caras (nivel de séptimas):');
    for (final c in peores) {
      stdout.writeln('  ${c.referencia.padRight(12)} → ${c.estimado.padRight(12)}'
          '${c.segundos.toStringAsFixed(1).padLeft(8)} s');
    }
  }
}

String _pct(double v) => '${(v * 100).toStringAsFixed(1)}%';

double? _leerDouble(List<String> args, String bandera) {
  final texto = _leerTexto(args, bandera);
  return texto == null ? null : double.tryParse(texto);
}

String? _leerTexto(List<String> args, String bandera) {
  final i = args.indexOf(bandera);
  if (i < 0 || i + 1 >= args.length) return null;
  return args[i + 1];
}

void _ayuda() {
  stdout.writeln('''
Banco de pruebas del motor de acordes.

  dart run bin/evaluar.dart <carpeta-del-corpus> [opciones]

El corpus es una carpeta con parejas cancion.wav + cancion.lab.
El .lab lleva una línea por acorde: "inicio fin etiqueta", que es justo lo
que exporta Audacity con Exportar etiquetas.

Opciones:
  --permanencia <n>       Probabilidad de no cambiar de acorde (0,96)
  --temperatura <n>       Cuánto se fía de cada frame (0,08)
  --umbral-silencio <n>   Energía por debajo de la cual se declara N (0,015)
  --guardar <carpeta>     Escribe los .lab estimados para poder oírlos
''');
}
