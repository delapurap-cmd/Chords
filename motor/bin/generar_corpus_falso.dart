import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

/// Genera un corpus sintético con sus etiquetas, para poder probar el banco de
/// pruebas antes de tener canciones reales.
///
/// No sirve para medir calidad: aquí no hay batería, ni voz, ni reverberación,
/// que es justo lo que hace difícil el problema. Sirve para comprobar que la
/// tubería completa está bien conectada.
///
///   dart run bin/generar_corpus_falso.dart ../corpus_falso
void main(List<String> argumentos) {
  final destino = argumentos.isEmpty ? '../corpus_falso' : argumentos.first;
  Directory(destino).createSync(recursive: true);

  final progresiones = <String, List<(String, List<int>)>>{
    'cadencia_mayor': [
      ('C:maj', [48, 52, 55]),
      ('F:maj', [53, 57, 60]),
      ('G:maj', [55, 59, 62]),
      ('C:maj', [48, 52, 55]),
    ],
    'menor_y_septimas': [
      ('A:min', [45, 48, 52]),
      ('D:min7', [50, 53, 57, 60]),
      ('G:7', [55, 59, 62, 65]),
      ('C:maj7', [48, 52, 55, 59]),
    ],
    'con_silencio': [
      ('N', <int>[]),
      ('E:min', [52, 55, 59]),
      ('N', <int>[]),
      ('A:maj', [57, 61, 64]),
    ],
  };

  const frecuencia = 22050;
  const segundosPorAcorde = 2.0;

  progresiones.forEach((nombre, acordes) {
    final muestras = Float64List((acordes.length * segundosPorAcorde * frecuencia).round());
    final etiquetas = StringBuffer();
    var cursor = 0;
    var t = 0.0;

    for (final (etiqueta, midis) in acordes) {
      final n = (segundosPorAcorde * frecuencia).round();
      for (var i = 0; i < n && cursor + i < muestras.length; i++) {
        if (midis.isEmpty) continue; // silencio
        final tiempo = i / frecuencia;
        var valor = 0.0;
        for (final midi in midis) {
          final f0 = 440.0 * math.pow(2, (midi - 69) / 12.0);
          for (var h = 1; h <= 3; h++) {
            valor += math.sin(2 * math.pi * f0 * h * tiempo) / (h * h);
          }
        }
        final rampa = math.min(1.0, math.min(i, n - i) / (frecuencia * 0.02));
        muestras[cursor + i] = valor / (midis.length * 2) * rampa;
      }
      etiquetas.writeln('${t.toStringAsFixed(3)}\t'
          '${(t + segundosPorAcorde).toStringAsFixed(3)}\t$etiqueta');
      cursor += n;
      t += segundosPorAcorde;
    }

    File('$destino/$nombre.wav').writeAsBytesSync(_wav(muestras, frecuencia));
    File('$destino/$nombre.lab').writeAsStringSync(etiquetas.toString());
    stdout.writeln('  $nombre.wav + $nombre.lab');
  });

  stdout.writeln('\nCorpus falso en $destino');
  stdout.writeln('Pruébalo con:  dart run bin/evaluar.dart $destino');
}

Uint8List _wav(Float64List muestras, int frecuencia) {
  final d = ByteData(44 + muestras.length * 2);
  void texto(int pos, String s) {
    for (var i = 0; i < s.length; i++) {
      d.setUint8(pos + i, s.codeUnitAt(i));
    }
  }

  texto(0, 'RIFF');
  d.setUint32(4, 36 + muestras.length * 2, Endian.little);
  texto(8, 'WAVE');
  texto(12, 'fmt ');
  d.setUint32(16, 16, Endian.little);
  d.setUint16(20, 1, Endian.little);
  d.setUint16(22, 1, Endian.little);
  d.setUint32(24, frecuencia, Endian.little);
  d.setUint32(28, frecuencia * 2, Endian.little);
  d.setUint16(32, 2, Endian.little);
  d.setUint16(34, 16, Endian.little);
  texto(36, 'data');
  d.setUint32(40, muestras.length * 2, Endian.little);
  for (var i = 0; i < muestras.length; i++) {
    d.setInt16(44 + i * 2, (muestras[i] * 32767).round().clamp(-32768, 32767), Endian.little);
  }
  return d.buffer.asUint8List();
}
