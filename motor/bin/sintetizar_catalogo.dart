import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:motor_acordes/motor_acordes.dart';

/// Genera el catálogo completo de more-than-modes como corpus de audio,
/// replicando al detalle la mezcla que hace `_generateStrumWav` en
/// `audio_controller.dart` (rasgueo grave→agudo, 20 ms de span, 48 kHz,
/// muestras acústicas "1*.wav", sin fade).
///
/// No es para medir si el motor "suena bien" — es la referencia simbólica
/// exacta (sabemos las notas MIDI de cada voicing porque las calculamos
/// nosotros mismos) para probar el modo de verificación contra las 2592
/// digitaciones sin que nadie tenga que grabarlas a mano. El pitch-shift no
/// cambia la altura real de la nota —para eso está—, así que sirve de sobra
/// para esto aunque el timbre no sea el de una guitarra real.
///
///   dart run bin/sintetizar_catalogo.dart \
///     --catalogo /home/user/more-than-modes/assets/chord_database.json \
///     --muestras /home/user/more-than-modes/assets/sounds/cuerdas \
///     --salida ../corpus_catalogo
void main(List<String> argumentos) {
  final args = _parsearArgs(argumentos);
  if (args == null) {
    _ayuda();
    exit(1);
  }

  final catalogoJson =
      jsonDecode(File(args.catalogo).readAsStringSync()) as Map<String, dynamic>;
  Directory(args.salida).createSync(recursive: true);

  stdout.writeln('Cargando muestras base de ${args.muestras}...');
  final muestras = _cargarMuestras(args.muestras);
  stdout.writeln('  ${muestras.length} muestras cargadas');
  stdout.writeln('');

  final manifiesto = File('${args.salida}/catalogo.jsonl').openWrite();
  var total = 0;
  var generadas = 0;
  var saltadas = 0;

  for (final calidadEntry in catalogoJson.entries) {
    final calidad = calidadEntry.key;
    if (args.calidades != null && !args.calidades!.contains(calidad)) continue;

    final porRaiz = calidadEntry.value as Map<String, dynamic>;
    for (final raizEntry in porRaiz.entries) {
      final raiz = raizEntry.key;
      final formas = (raizEntry.value as List).cast<String>();

      for (var indice = 0; indice < formas.length; indice++) {
        total++;
        if (args.limite != null && generadas >= args.limite!) continue;

        final texto = formas[indice];
        final Voicing voicing;
        try {
          voicing = Voicing.deTexto(texto);
        } catch (e) {
          stderr.writeln('  $calidad/$raiz#$indice: forma ilegible "$texto" ($e)');
          saltadas++;
          continue;
        }
        if (voicing.esSilencio) {
          saltadas++;
          continue;
        }

        final Audio audio;
        try {
          audio = _generarRasgueo(voicing, muestras);
        } catch (e) {
          stderr.writeln('  $calidad/$raiz#$indice ($texto): $e');
          saltadas++;
          continue;
        }

        final nombreCarpeta = _slug(calidad);
        final nombreArchivo = '${_slug(raiz)}_$indice.wav';
        final carpetaCalidad = Directory('${carpelaConBarra(args.salida)}$nombreCarpeta')
          ..createSync(recursive: true);
        final rutaWav = '${carpelaConBarra(carpetaCalidad.path)}$nombreArchivo';
        escribirWavAArchivo(audio, rutaWav);

        final notas = notasMidiDeVoicing(voicing);
        manifiesto.writeln(jsonEncode({
          'calidad': calidad,
          'raiz': raiz,
          'indice': indice,
          'forma': texto,
          'archivo': '$nombreCarpeta/$nombreArchivo',
          'notasMidi': notas,
          'duracionSegundos': audio.duracion,
        }));
        generadas++;
      }
    }
  }

  manifiesto.close();

  stdout.writeln('');
  stdout.writeln('─' * 50);
  stdout.writeln('Generadas: $generadas / $total');
  if (saltadas > 0) stdout.writeln('Saltadas: $saltadas (silencio total o forma ilegible)');
  stdout.writeln('Manifiesto: ${args.salida}/catalogo.jsonl');
}

// ─── La mezcla, réplica exacta de _generateStrumWav ─────────────────────────

/// Traste a partir del cual una cuerda "cabalga" sobre la muestra de la
/// cuerda adyacente más aguda — el mismo umbral que `_getSoundParams`.
({String archivo, int semitonos}) _paramsCuerda(int cuerda, int traste) {
  switch (cuerda) {
    case 0:
      return (archivo: '1Eagudo.wav', semitonos: traste);
    case 1:
      return traste >= 5
          ? (archivo: '1Eagudo.wav', semitonos: traste - 5)
          : (archivo: '1B.wav', semitonos: traste);
    case 2:
      return traste >= 4
          ? (archivo: '1B.wav', semitonos: traste - 4)
          : (archivo: '1G.wav', semitonos: traste);
    case 3:
      return traste >= 5
          ? (archivo: '1G.wav', semitonos: traste - 5)
          : (archivo: '1D.wav', semitonos: traste);
    case 4:
      return traste >= 5
          ? (archivo: '1D.wav', semitonos: traste - 5)
          : (archivo: '1A.wav', semitonos: traste);
    case 5:
      return traste >= 5
          ? (archivo: '1A.wav', semitonos: traste - 5)
          : (archivo: '1E grave.wav', semitonos: traste);
    default:
      throw ArgumentError('cuerda inválida: $cuerda');
  }
}

const int _sampleRate = 48000;
const int _strumMs = 20;
const double _volumenCuerda = 0.70;

Audio _generarRasgueo(Voicing v, Map<String, Audio> muestras) {
  // Orden grave→agudo, igual que `reversed=false` en la app (el valor por
  // defecto, y el que usa `playChordInstant` al no pasar el parámetro).
  final activas = [for (var i = 5; i >= 0; i--) if (v.trastes[i] != -1) i];

  final totalStrumSamples = (_strumMs * _sampleRate / 1000).round();
  final delayPerString =
      activas.length > 1 ? totalStrumSamples ~/ (activas.length - 1) : 0;
  const noteDurationSamples = _sampleRate * 2;
  final bufferSamples = noteDurationSamples + totalStrumSamples;
  final buffer = Float64List(bufferSamples);

  for (var i = 0; i < activas.length; i++) {
    final cuerda = activas[i];
    final traste = v.trastes[cuerda];
    final params = _paramsCuerda(cuerda, traste);
    final base = muestras[params.archivo];
    if (base == null) {
      throw StateError('falta la muestra "${params.archivo}"');
    }
    final inicio = i * delayPerString;
    final tasa = math.pow(2.0, params.semitonos / 12.0).toDouble();
    _mezclarResampleado(buffer, inicio, base.muestras, tasa, _volumenCuerda);
  }

  return Audio(buffer, _sampleRate);
}

/// Misma lógica que `_mixResampled`: interpolación lineal a la velocidad
/// dada, corte duro al acabarse la fuente o el buffer — sin fade.
void _mezclarResampleado(
  Float64List destino,
  int inicio,
  Float64List fuente,
  double tasa,
  double volumen,
) {
  var srcPos = 0.0;
  var outIdx = inicio;
  while (outIdx < destino.length && srcPos < fuente.length - 1) {
    final j = srcPos.floor();
    final resto = srcPos - j;
    final muestra = fuente[j] + (fuente[j + 1] - fuente[j]) * resto;
    destino[outIdx] += muestra * volumen;
    outIdx++;
    srcPos += tasa;
  }
}

// ─── Utilidades ───────────────────────────────────────────────────────────

Map<String, Audio> _cargarMuestras(String carpeta) {
  const nombres = [
    '1Eagudo.wav',
    '1B.wav',
    '1G.wav',
    '1D.wav',
    '1A.wav',
    '1E grave.wav',
  ];
  final salida = <String, Audio>{};
  for (final nombre in nombres) {
    final archivo = File('${carpelaConBarra(carpeta)}$nombre');
    if (!archivo.existsSync()) {
      stderr.writeln('Falta la muestra base: ${archivo.path}');
      exit(1);
    }
    salida[nombre] = leerWav(archivo.readAsBytesSync());
  }
  return salida;
}

String carpelaConBarra(String ruta) => ruta.endsWith('/') ? ruta : '$ruta/';

/// Nombre de archivo seguro: fuera espacios, "/", "#" y "+", que aparecen en
/// nombres reales del catálogo ("6/9", "C#", "7#9", "7#5").
String _slug(String s) => s
    .replaceAll('/', '-')
    .replaceAll('#', 'sost')
    .replaceAll('+', 'mas')
    .replaceAll(' ', '_');

class _Args {
  final String catalogo;
  final String muestras;
  final String salida;
  final Set<String>? calidades;
  final int? limite;

  _Args({
    required this.catalogo,
    required this.muestras,
    required this.salida,
    this.calidades,
    this.limite,
  });
}

_Args? _parsearArgs(List<String> argumentos) {
  String? catalogo, muestras, salida, calidades, limiteTexto;
  for (var i = 0; i < argumentos.length; i++) {
    switch (argumentos[i]) {
      case '--catalogo':
        catalogo = argumentos[++i];
      case '--muestras':
        muestras = argumentos[++i];
      case '--salida':
        salida = argumentos[++i];
      case '--calidades':
        calidades = argumentos[++i];
      case '--limite':
        limiteTexto = argumentos[++i];
      case '--ayuda':
      case '-h':
        return null;
    }
  }
  if (catalogo == null || muestras == null || salida == null) return null;
  return _Args(
    catalogo: catalogo,
    muestras: muestras,
    salida: salida,
    calidades: calidades?.split(',').map((s) => s.trim()).toSet(),
    limite: limiteTexto == null ? null : int.parse(limiteTexto),
  );
}

void _ayuda() {
  stdout.writeln('''
Genera el catálogo de more-than-modes como corpus de audio.

  dart run bin/sintetizar_catalogo.dart \\
    --catalogo <ruta a chord_database.json> \\
    --muestras <carpeta con las 6 muestras "1*.wav"> \\
    --salida <carpeta de salida> \\
    [--calidades Mayor,Menor,...] \\
    [--limite N]

--calidades filtra a solo esas calidades (nombres tal cual están en el
JSON: Mayor, Menor, Maj7, 7, m7, m7b5, dim7, mMaj7, sus2, sus4, 7sus4,
add9, 9, m9, 7#9, 7b9, 11, m11, 13, m13, 13b9, 6, m6, 6/9, aug, 7#5, 7b5,
Maj9, 5, madd9).

--limite corta después de generar N clips, para una prueba rápida antes de
lanzar las 2592.
''');
}
