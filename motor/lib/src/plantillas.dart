import 'dart:math' as math;
import 'dart:typed_data';

/// Vocabulario del v0: las cinco calidades que cubren la inmensa mayoría de
/// la música popular, por doce fundamentales, más el silencio.
///
/// Empezar aquí y no con el vocabulario completo es deliberado. Con 61 clases
/// ya se puede medir el nivel de séptimas, que es donde se juega lo de
/// "acordes complejos", y cada clase que se añade necesita datos que la
/// respalden. Ampliar es fácil; medir sin línea base, no.
const List<String> calidadesDelVocabulario = ['maj', 'min', 'maj7', 'min7', '7'];

const List<String> nombresDeFundamental = [
  'C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'
];

/// Intervalos de cada calidad, en semitonos sobre la fundamental.
const Map<String, List<int>> _intervalosPorCalidad = {
  'maj': [0, 4, 7],
  'min': [0, 3, 7],
  'maj7': [0, 4, 7, 11],
  'min7': [0, 3, 7, 10],
  '7': [0, 4, 7, 10],
};

/// Una clase del vocabulario con su plantilla de croma.
class Plantilla {
  /// Etiqueta en notación Harte, lista para escribir en un `.lab`.
  final String etiqueta;

  /// Vector de 12, normalizado. -1 en fundamental para el silencio.
  final Float64List croma;

  final int fundamental;

  const Plantilla(this.etiqueta, this.croma, this.fundamental);

  bool get esSilencio => fundamental < 0;
}

/// Construye el vocabulario completo: 12 fundamentales × 5 calidades + N.
List<Plantilla> construirVocabulario() {
  final salida = <Plantilla>[];

  for (var fundamental = 0; fundamental < 12; fundamental++) {
    for (final calidad in calidadesDelVocabulario) {
      final intervalos = _intervalosPorCalidad[calidad]!;
      final croma = Float64List(12);
      for (final iv in intervalos) {
        croma[(fundamental + iv) % 12] = 1.0;
      }
      // La fundamental y la quinta pesan más porque son las que sobreviven a
      // una mezcla con batería y voz encima.
      croma[fundamental] = 1.3;
      croma[(fundamental + 7) % 12] = math.max(croma[(fundamental + 7) % 12], 1.1);
      _normalizar(croma);
      salida.add(Plantilla(
        '${nombresDeFundamental[fundamental]}:$calidad',
        croma,
        fundamental,
      ));
    }
  }

  // El silencio no es un patrón de croma, es ausencia de estructura: se marca
  // con un vector plano y se trata aparte al puntuar.
  final plano = Float64List(12);
  for (var i = 0; i < 12; i++) {
    plano[i] = 1.0;
  }
  _normalizar(plano);
  salida.add(Plantilla('N', plano, -1));

  return salida;
}

void _normalizar(Float64List v) {
  var suma = 0.0;
  for (final x in v) {
    suma += x * x;
  }
  final norma = math.sqrt(suma);
  if (norma > 1e-12) {
    for (var i = 0; i < v.length; i++) {
      v[i] /= norma;
    }
  }
}

/// Similitud del coseno entre un frame de croma y una plantilla.
double similitud(Float64List croma, Float64List plantilla) {
  var punto = 0.0;
  var normaCroma = 0.0;
  for (var i = 0; i < 12; i++) {
    punto += croma[i] * plantilla[i];
    normaCroma += croma[i] * croma[i];
  }
  normaCroma = math.sqrt(normaCroma);
  if (normaCroma < 1e-12) return 0.0;
  return punto / normaCroma; // la plantilla ya viene normalizada
}
