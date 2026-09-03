import 'dart:math' as math;
import 'dart:typed_data';

/// Decodificador de Viterbi.
///
/// Sin esto la salida parpadea: el mejor acorde frame a frame cambia
/// constantemente porque la voz entra, el bombo pega o suena una nota de
/// paso. El Viterbi impone que cambiar de acorde cuesta, así que solo cambia
/// cuando la evidencia acumulada lo justifica. Es la diferencia entre una
/// lista de ruido y un cifrado legible.
class Viterbi {
  /// Log-probabilidad de quedarse en el mismo acorde en el siguiente frame.
  /// Cuanto más cerca de 0, más pegajoso.
  final double logPermanencia;

  /// Log-probabilidad de saltar a cualquier otro acorde.
  final double logCambio;

  Viterbi._(this.logPermanencia, this.logCambio);

  /// [permanencia] es la probabilidad de no cambiar de acorde entre frames.
  ///
  /// Con frames de 93 ms y acordes que duran uno o dos segundos, lo razonable
  /// está por encima de 0,9. Es el parámetro que más cambia la salida, y el
  /// primero que hay que barrer contra el corpus.
  factory Viterbi({required int numeroDeClases, double permanencia = 0.96}) {
    if (numeroDeClases < 2) {
      throw ArgumentError('Hacen falta al menos dos clases');
    }
    if (permanencia <= 0 || permanencia >= 1) {
      throw ArgumentError('La permanencia debe estar entre 0 y 1, sin incluirlos');
    }
    final cambio = (1.0 - permanencia) / (numeroDeClases - 1);
    return Viterbi._(math.log(permanencia), math.log(cambio));
  }

  /// Devuelve la secuencia de clases más probable.
  ///
  /// [logEmisiones] tiene un vector por frame, con una log-probabilidad por
  /// clase. La transición es uniforme, así que no hace falta materializar la
  /// matriz K×K: en cada paso solo importa el mejor anterior y el propio.
  List<int> decodificar(List<Float64List> logEmisiones) {
    if (logEmisiones.isEmpty) return const [];
    final t = logEmisiones.length;
    final k = logEmisiones.first.length;

    var anterior = Float64List(k)..setAll(0, logEmisiones.first);
    // Un byte por frame y clase: para una canción de cinco minutos son unos
    // 200 KB, frente a los megas que ocuparía con enteros de 64 bits.
    final rastro = List<Uint8List>.generate(t, (_) => Uint8List(k), growable: false);

    for (var i = 1; i < t; i++) {
      // El mejor estado anterior sirve para todos los destinos, porque la
      // probabilidad de cambio es la misma hacia cualquiera.
      var mejor = anterior[0];
      var indiceMejor = 0;
      for (var j = 1; j < k; j++) {
        if (anterior[j] > mejor) {
          mejor = anterior[j];
          indiceMejor = j;
        }
      }

      final actual = Float64List(k);
      final emision = logEmisiones[i];
      for (var j = 0; j < k; j++) {
        final quedandose = anterior[j] + logPermanencia;
        final saltando = mejor + logCambio;
        if (quedandose >= saltando) {
          actual[j] = quedandose + emision[j];
          rastro[i][j] = j;
        } else {
          actual[j] = saltando + emision[j];
          rastro[i][j] = indiceMejor;
        }
      }
      anterior = actual;
    }

    var mejorFinal = 0;
    for (var j = 1; j < k; j++) {
      if (anterior[j] > anterior[mejorFinal]) mejorFinal = j;
    }

    final camino = List<int>.filled(t, 0);
    camino[t - 1] = mejorFinal;
    for (var i = t - 1; i > 0; i--) {
      camino[i - 1] = rastro[i][camino[i]];
    }
    return camino;
  }
}

/// Pasa puntuaciones sin normalizar a log-probabilidades.
///
/// [temperatura] controla cuánto se fía el decodificador de la evidencia de
/// cada frame: baja la hace muy segura de sí misma y el Viterbi deja de
/// suavizar; alta aplana todo y manda la permanencia.
Float64List aLogProbabilidades(Float64List puntuaciones, {double temperatura = 0.08}) {
  final k = puntuaciones.length;
  final escaladas = Float64List(k);
  var maximo = double.negativeInfinity;
  for (var i = 0; i < k; i++) {
    escaladas[i] = puntuaciones[i] / temperatura;
    if (escaladas[i] > maximo) maximo = escaladas[i];
  }
  // Se resta el máximo antes de exponenciar para no desbordar.
  var suma = 0.0;
  for (var i = 0; i < k; i++) {
    escaladas[i] -= maximo;
    suma += math.exp(escaladas[i]);
  }
  final logSuma = math.log(suma);
  for (var i = 0; i < k; i++) {
    escaladas[i] -= logSuma;
  }
  return escaladas;
}
