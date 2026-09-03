import 'dart:math' as math;
import 'dart:typed_data';

import 'fft.dart';
import 'wav.dart';

/// Ajustes del análisis espectral.
class AjustesDeCromagrama {
  /// 11025 Hz sobra: el contenido armónico que sirve para acordes vive por
  /// debajo de 2 kHz. Bajar la frecuencia acelera la FFT y no pierde nada.
  final int frecuencia;

  /// 4096 muestras a 11025 Hz son 372 ms de ventana. Largo, pero hace falta
  /// resolución en frecuencia para separar semitonos en el registro grave.
  final int tamanoDeVentana;

  /// 1024 muestras son 93 ms de salto: unos 11 frames por segundo.
  final int salto;

  /// Nota MIDI más grave que se mira. 24 = do1, unos 33 Hz.
  final int notaMinima;

  /// Nota MIDI más aguda. 96 = do7, unos 2093 Hz.
  final int notaMaxima;

  const AjustesDeCromagrama({
    this.frecuencia = 11025,
    this.tamanoDeVentana = 4096,
    this.salto = 1024,
    this.notaMinima = 24,
    this.notaMaxima = 96,
  });

  double get segundosPorFrame => salto / frecuencia;
}

/// Cromagrama: energía por clase de altura a lo largo del tiempo.
class Cromagrama {
  /// Un vector de 12 por frame, normalizado.
  final List<Float64List> frames;

  /// Lo mismo pero solo con el registro grave, para adivinar el bajo.
  final List<Float64List> framesDeBajo;

  final double segundosPorFrame;

  const Cromagrama(this.frames, this.framesDeBajo, this.segundosPorFrame);

  int get largo => frames.length;

  double tiempoDe(int frame) => frame * segundosPorFrame;
}

/// Convierte audio en cromagrama.
///
/// Es un cromagrama por banco de filtros de semitono, no el NNLS de Chordino.
/// Es la línea base honesta: si un modelo entrenado no le gana a esto por
/// mucho, es que el modelo está mal montado.
Cromagrama calcularCromagrama(Audio audio, {AjustesDeCromagrama ajustes = const AjustesDeCromagrama()}) {
  final a = remuestrear(audio, ajustes.frecuencia);
  final fft = Fft(ajustes.tamanoDeVentana);
  final ventana = ventanaHann(ajustes.tamanoDeVentana);
  final banco = _bancoDeSemitonos(ajustes);

  // Hasta do4 se considera registro de bajo.
  final limiteDeBajo = 48 - ajustes.notaMinima;

  final frames = <Float64List>[];
  final framesDeBajo = <Float64List>[];
  final buffer = Float64List(ajustes.tamanoDeVentana);

  for (var inicio = 0;
      inicio + ajustes.tamanoDeVentana <= a.muestras.length;
      inicio += ajustes.salto) {
    for (var i = 0; i < ajustes.tamanoDeVentana; i++) {
      buffer[i] = a.muestras[inicio + i] * ventana[i];
    }
    final espectro = fft.magnitud(buffer);

    // Energía por semitono.
    final notas = Float64List(banco.length);
    for (var n = 0; n < banco.length; n++) {
      var suma = 0.0;
      final filtro = banco[n];
      for (var k = 0; k < filtro.indices.length; k++) {
        suma += espectro[filtro.indices[k]] * filtro.pesos[k];
      }
      notas[n] = suma;
    }

    frames.add(_plegarACroma(notas, ajustes.notaMinima, 0, notas.length));
    framesDeBajo.add(_plegarACroma(notas, ajustes.notaMinima, 0,
        math.min(limiteDeBajo, notas.length)));
  }

  return Cromagrama(frames, framesDeBajo, ajustes.segundosPorFrame);
}

/// Suma los semitonos en las 12 clases y normaliza el frame.
Float64List _plegarACroma(Float64List notas, int notaMinima, int desde, int hasta) {
  final croma = Float64List(12);
  for (var n = desde; n < hasta; n++) {
    croma[(notaMinima + n) % 12] += notas[n];
  }
  // Normalizar por el máximo deja cada frame comparable con los demás sin que
  // los pasajes fuertes pesen más que los suaves.
  var maximo = 0.0;
  for (final v in croma) {
    if (v > maximo) maximo = v;
  }
  if (maximo > 1e-12) {
    for (var i = 0; i < 12; i++) {
      croma[i] /= maximo;
    }
  }
  return croma;
}

class _Filtro {
  final Int32List indices;
  final Float64List pesos;
  const _Filtro(this.indices, this.pesos);
}

/// Un filtro triangular por semitono, centrado en su frecuencia y ancho medio
/// semitono a cada lado. Es la forma barata de pasar de bins lineales de FFT
/// a una escala logarítmica sin montar una CQT entera.
List<_Filtro> _bancoDeSemitonos(AjustesDeCromagrama ajustes) {
  final bins = ajustes.tamanoDeVentana ~/ 2 + 1;
  final hzPorBin = ajustes.frecuencia / ajustes.tamanoDeVentana;
  final salida = <_Filtro>[];

  for (var nota = ajustes.notaMinima; nota <= ajustes.notaMaxima; nota++) {
    final centro = 440.0 * math.pow(2, (nota - 69) / 12.0);
    final abajo = centro * math.pow(2, -0.5 / 12.0);
    final arriba = centro * math.pow(2, 0.5 / 12.0);

    final indices = <int>[];
    final pesos = <double>[];
    final primero = (abajo / hzPorBin).floor().clamp(0, bins - 1);
    final ultimo = (arriba / hzPorBin).ceil().clamp(0, bins - 1);

    for (var k = primero; k <= ultimo; k++) {
      final hz = k * hzPorBin;
      if (hz < abajo || hz > arriba) continue;
      // Triángulo: 1 en el centro, 0 en los extremos.
      final peso = hz <= centro
          ? (hz - abajo) / (centro - abajo)
          : (arriba - hz) / (arriba - centro);
      if (peso <= 0) continue;
      indices.add(k);
      pesos.add(peso);
    }

    // En el registro grave un semitono puede ser más estrecho que un bin y
    // quedarse sin ninguno. Se coge el más cercano para no dejar el hueco.
    if (indices.isEmpty) {
      final k = (centro / hzPorBin).round().clamp(0, bins - 1);
      indices.add(k);
      pesos.add(1.0);
    }

    salida.add(_Filtro(Int32List.fromList(indices), Float64List.fromList(pesos)));
  }
  return salida;
}
