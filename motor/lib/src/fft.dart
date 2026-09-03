import 'dart:math' as math;
import 'dart:typed_data';

/// FFT de raíz 2, iterativa y en el sitio.
///
/// Se escribe a mano porque el motor no puede depender de nada externo: tiene
/// que correr igual bajo `dart test` y dentro del móvil sin conexión.
class Fft {
  final int n;
  final Float64List _cos;
  final Float64List _sin;
  final Int32List _invertido;

  Fft(this.n)
      : _cos = Float64List(n ~/ 2),
        _sin = Float64List(n ~/ 2),
        _invertido = Int32List(n) {
    if (n < 2 || (n & (n - 1)) != 0) {
      throw ArgumentError('El tamaño de FFT debe ser potencia de 2, recibido $n');
    }
    for (var i = 0; i < n ~/ 2; i++) {
      _cos[i] = math.cos(-2 * math.pi * i / n);
      _sin[i] = math.sin(-2 * math.pi * i / n);
    }
    final bits = (math.log(n) / math.ln2).round();
    for (var i = 0; i < n; i++) {
      var x = i;
      var r = 0;
      for (var b = 0; b < bits; b++) {
        r = (r << 1) | (x & 1);
        x >>= 1;
      }
      _invertido[i] = r;
    }
  }

  /// Transforma [real] e [imaginaria] en el sitio. Las dos deben medir [n].
  void transformar(Float64List real, Float64List imaginaria) {
    for (var i = 0; i < n; i++) {
      final j = _invertido[i];
      if (j > i) {
        var t = real[i];
        real[i] = real[j];
        real[j] = t;
        t = imaginaria[i];
        imaginaria[i] = imaginaria[j];
        imaginaria[j] = t;
      }
    }

    for (var tam = 2; tam <= n; tam <<= 1) {
      final mitad = tam ~/ 2;
      final paso = n ~/ tam;
      for (var i = 0; i < n; i += tam) {
        for (var j = i, k = 0; j < i + mitad; j++, k += paso) {
          final c = _cos[k];
          final s = _sin[k];
          final ar = real[j + mitad] * c - imaginaria[j + mitad] * s;
          final ai = real[j + mitad] * s + imaginaria[j + mitad] * c;
          real[j + mitad] = real[j] - ar;
          imaginaria[j + mitad] = imaginaria[j] - ai;
          real[j] += ar;
          imaginaria[j] += ai;
        }
      }
    }
  }

  /// Magnitud de los `n/2 + 1` bins útiles de una señal real.
  Float64List magnitud(Float64List muestras) {
    final re = Float64List(n)..setRange(0, math.min(n, muestras.length), muestras);
    final im = Float64List(n);
    transformar(re, im);
    final salida = Float64List(n ~/ 2 + 1);
    for (var i = 0; i < salida.length; i++) {
      salida[i] = math.sqrt(re[i] * re[i] + im[i] * im[i]);
    }
    return salida;
  }
}

/// Ventana de Hann, para que los bordes de cada frame no ensucien el espectro.
Float64List ventanaHann(int n) {
  final v = Float64List(n);
  for (var i = 0; i < n; i++) {
    v[i] = 0.5 - 0.5 * math.cos(2 * math.pi * i / (n - 1));
  }
  return v;
}
