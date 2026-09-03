import 'dart:math' as math;
import 'dart:typed_data';

import 'package:motor_acordes/motor_acordes.dart';
import 'package:test/test.dart';

/// Sintetiza una secuencia de acordes con armónicos, para poder probar la
/// tubería entera sin depender de tener el corpus a mano.
///
/// No sustituye a las canciones reales — aquí no hay batería, ni voz, ni
/// reverberación — pero sí detecta lo que más rompe: fundamentales cambiadas,
/// octavas mal plegadas y el Viterbi al revés.
Audio sintetizar(List<({List<int> midis, double segundos})> acordes, {int frecuencia = 22050}) {
  final total = acordes.fold<double>(0, (s, a) => s + a.segundos);
  final muestras = Float64List((total * frecuencia).round());
  var cursor = 0;

  for (final acorde in acordes) {
    final n = (acorde.segundos * frecuencia).round();
    for (var i = 0; i < n && cursor + i < muestras.length; i++) {
      final t = i / frecuencia;
      var valor = 0.0;
      for (final midi in acorde.midis) {
        final f0 = 440.0 * math.pow(2, (midi - 69) / 12.0);
        // Tres armónicos con caída: se parece más a una cuerda que un seno.
        for (var h = 1; h <= 3; h++) {
          valor += math.sin(2 * math.pi * f0 * h * t) / (h * h);
        }
      }
      // Entrada y salida suaves para que no haya chasquidos en los bordes.
      final rampa = math.min(1.0, math.min(i, n - i) / (frecuencia * 0.02));
      muestras[cursor + i] = valor / (acorde.midis.length * 2) * rampa;
    }
    cursor += n;
  }
  return Audio(muestras, frecuencia);
}

void main() {
  group('FFT', () {
    test('encuentra el bin de un seno puro', () {
      const n = 1024;
      const frecuencia = 8192;
      const hz = 512.0;
      final senal = Float64List(n);
      for (var i = 0; i < n; i++) {
        senal[i] = math.sin(2 * math.pi * hz * i / frecuencia);
      }
      final mag = Fft(n).magnitud(senal);
      var pico = 0;
      for (var i = 1; i < mag.length; i++) {
        if (mag[i] > mag[pico]) pico = i;
      }
      expect(pico * frecuencia / n, closeTo(hz, frecuencia / n));
    });
  });

  group('WAV', () {
    test('ida y vuelta de 16 bits mono', () {
      final original = Float64List.fromList([0.0, 0.5, -0.5, 0.999, -0.999]);
      final bytes = _wavDePrueba(original, 22050);
      final leido = leerWav(bytes);
      expect(leido.frecuencia, 22050);
      expect(leido.muestras.length, original.length);
      for (var i = 0; i < original.length; i++) {
        expect(leido.muestras[i], closeTo(original[i], 1e-4));
      }
    });
  });

  group('Viterbi', () {
    test('sigue la evidencia cuando es clara y constante', () {
      final emisiones = List.generate(10, (_) {
        final v = Float64List(3);
        v[1] = 0.0;
        v[0] = -5.0;
        v[2] = -5.0;
        return v;
      });
      final camino = Viterbi(numeroDeClases: 3, permanencia: 0.9).decodificar(emisiones);
      expect(camino, everyElement(1));
    });

    test('aguanta un frame suelto en contra en vez de saltar', () {
      // Nueve frames dicen clase 0 y uno dice clase 1: sin suavizado la salida
      // parpadearía justo ahí. Con Viterbi no.
      final emisiones = List.generate(10, (i) {
        final v = Float64List(2);
        if (i == 5) {
          v[0] = -1.0;
          v[1] = 0.0;
        } else {
          v[0] = 0.0;
          v[1] = -1.0;
        }
        return v;
      });
      final camino = Viterbi(numeroDeClases: 2, permanencia: 0.99).decodificar(emisiones);
      expect(camino, everyElement(0), reason: 'un frame aislado no debe mover el acorde');
    });

    test('sí cambia cuando la evidencia cambia de verdad', () {
      final emisiones = List.generate(20, (i) {
        final v = Float64List(2);
        if (i < 10) {
          v[0] = 0.0;
          v[1] = -3.0;
        } else {
          v[0] = -3.0;
          v[1] = 0.0;
        }
        return v;
      });
      final camino = Viterbi(numeroDeClases: 2, permanencia: 0.95).decodificar(emisiones);
      expect(camino.first, 0);
      expect(camino.last, 1);
    });

    test('rechaza parámetros imposibles', () {
      expect(() => Viterbi(numeroDeClases: 1), throwsArgumentError);
      expect(() => Viterbi(numeroDeClases: 3, permanencia: 1.0), throwsArgumentError);
    });
  });

  group('cromagrama', () {
    test('un do mayor enciende do, mi y sol', () {
      final audio = sintetizar([
        (midis: [48, 52, 55], segundos: 2.0), // do3 mi3 sol3
      ]);
      final croma = calcularCromagrama(audio);
      expect(croma.largo, greaterThan(5));

      // Se promedia el centro para saltarse las rampas de entrada y salida.
      final medio = Float64List(12);
      final desde = croma.largo ~/ 4;
      final hasta = croma.largo * 3 ~/ 4;
      for (var f = desde; f < hasta; f++) {
        for (var i = 0; i < 12; i++) {
          medio[i] += croma.frames[f][i];
        }
      }

      final orden = List.generate(12, (i) => i)..sort((a, b) => medio[b].compareTo(medio[a]));
      expect(orden.take(3).toSet(), {0, 4, 7},
          reason: 'las tres clases con más energía deben ser do, mi y sol');
    });
  });

  group('motor de punta a punta', () {
    test('reconoce una secuencia sintética de mayores y menores', () {
      final audio = sintetizar([
        (midis: [48, 52, 55], segundos: 2.0), // C:maj
        (midis: [53, 57, 60], segundos: 2.0), // F:maj
        (midis: [55, 59, 62], segundos: 2.0), // G:maj
        (midis: [45, 48, 52], segundos: 2.0), // A:min
      ]);

      final tramos = MotorV0().analizar(audio);
      expect(tramos, isNotEmpty);

      final referencia = leerLab(
        '0.0 2.0 C:maj\n2.0 4.0 F:maj\n4.0 6.0 G:maj\n6.0 8.0 A:min\n',
      );
      final nota = evaluar(referencia, tramos);

      // El umbral es flojo a propósito: esto mide que la tubería funciona, no
      // que el v0 sea bueno. Lo bueno o malo lo dirá el corpus real.
      expect(nota[Nivel.fundamental]!.wcsr, greaterThan(0.7),
          reason: 'con audio limpio la fundamental debería salir casi siempre');
      expect(nota[Nivel.mayorMenor]!.wcsr, greaterThan(0.6));
    });

    test('la salida cubre el audio sin huecos ni solapes', () {
      final audio = sintetizar([
        (midis: [48, 52, 55], segundos: 1.5),
        (midis: [50, 53, 57], segundos: 1.5),
      ]);
      final tramos = MotorV0().analizar(audio);
      for (var i = 1; i < tramos.length; i++) {
        expect(tramos[i].inicio, closeTo(tramos[i - 1].fin, 1e-6),
            reason: 'los tramos deben ir pegados');
      }
      expect(tramos.first.inicio, closeTo(0.0, 1e-6));
    });

    test('las etiquetas que produce el motor son notación válida', () {
      final audio = sintetizar([(midis: [48, 52, 55], segundos: 1.0)]);
      for (final t in MotorV0().analizar(audio)) {
        expect(() => interpretarAcorde(t.etiqueta), returnsNormally);
      }
    });

    test('el silencio se detecta como N', () {
      final mudo = Audio(Float64List((22050 * 2).round()), 22050);
      final tramos = MotorV0().analizar(mudo);
      expect(tramos.every((t) => t.etiqueta == 'N'), isTrue,
          reason: 'audio en silencio no puede producir acordes');
    });
  });
}

/// WAV PCM 16 bits mono mínimo, para el test de ida y vuelta.
Uint8List _wavDePrueba(Float64List muestras, int frecuencia) {
  final datos = ByteData(44 + muestras.length * 2);
  void texto(int pos, String s) {
    for (var i = 0; i < s.length; i++) {
      datos.setUint8(pos + i, s.codeUnitAt(i));
    }
  }

  texto(0, 'RIFF');
  datos.setUint32(4, 36 + muestras.length * 2, Endian.little);
  texto(8, 'WAVE');
  texto(12, 'fmt ');
  datos.setUint32(16, 16, Endian.little);
  datos.setUint16(20, 1, Endian.little); // PCM
  datos.setUint16(22, 1, Endian.little); // mono
  datos.setUint32(24, frecuencia, Endian.little);
  datos.setUint32(28, frecuencia * 2, Endian.little);
  datos.setUint16(32, 2, Endian.little);
  datos.setUint16(34, 16, Endian.little);
  texto(36, 'data');
  datos.setUint32(40, muestras.length * 2, Endian.little);
  for (var i = 0; i < muestras.length; i++) {
    datos.setInt16(44 + i * 2, (muestras[i] * 32767).round().clamp(-32768, 32767), Endian.little);
  }
  return datos.buffer.asUint8List();
}
