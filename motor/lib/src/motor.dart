import 'dart:typed_data';

import 'cromagrama.dart';
import 'lab.dart';
import 'plantillas.dart';
import 'viterbi.dart';
import 'wav.dart';

/// Lo que se puede ajustar del reconocedor v0. Todo lo que aparezca aquí es
/// candidato a barrerse contra el corpus.
class AjustesDelMotor {
  final AjustesDeCromagrama cromagrama;

  /// Probabilidad de no cambiar de acorde entre frames.
  final double permanencia;

  /// Cuánto se fía de la evidencia de cada frame.
  final double temperatura;

  /// Por debajo de esta energía se declara silencio en vez de inventar un
  /// acorde. Es lo que evita que las intros y las colas ensucien la nota.
  final double umbralDeSilencio;

  const AjustesDelMotor({
    this.cromagrama = const AjustesDeCromagrama(),
    this.permanencia = 0.96,
    this.temperatura = 0.08,
    this.umbralDeSilencio = 0.015,
  });

  AjustesDelMotor copiarCon({double? permanencia, double? temperatura, double? umbralDeSilencio}) {
    return AjustesDelMotor(
      cromagrama: cromagrama,
      permanencia: permanencia ?? this.permanencia,
      temperatura: temperatura ?? this.temperatura,
      umbralDeSilencio: umbralDeSilencio ?? this.umbralDeSilencio,
    );
  }
}

/// Reconocedor v0: cromagrama, plantillas y Viterbi. Sin modelo entrenado.
///
/// Existe para dos cosas: cerrar la tubería completa de audio a `.lab`, y dar
/// un número contra el que compita cualquier cosa que venga después. Si el
/// modelo con IA no le gana a esto con holgura, el problema está en el modelo
/// o en cómo se le dan los datos, no en la tarea.
class MotorV0 {
  final AjustesDelMotor ajustes;
  final List<Plantilla> vocabulario;

  MotorV0({this.ajustes = const AjustesDelMotor()})
      : vocabulario = construirVocabulario();

  /// Analiza audio ya decodificado y devuelve el cifrado en tramos.
  List<Tramo> analizar(Audio audio) {
    final croma = calcularCromagrama(audio, ajustes: ajustes.cromagrama);
    if (croma.largo == 0) return const [];

    final indiceDeSilencio = vocabulario.indexWhere((p) => p.esSilencio);
    final energias = _energiaPorFrame(croma, audio);

    final emisiones = <Float64List>[];
    for (var f = 0; f < croma.largo; f++) {
      final puntuaciones = Float64List(vocabulario.length);
      for (var c = 0; c < vocabulario.length; c++) {
        final p = vocabulario[c];
        puntuaciones[c] = p.esSilencio
            // El silencio no compite por parecido de croma: compite por falta
            // de energía. Si el frame suena, su puntuación se hunde.
            ? (energias[f] < ajustes.umbralDeSilencio ? 1.0 : 0.0)
            : similitud(croma.frames[f], p.croma) *
                (energias[f] < ajustes.umbralDeSilencio ? 0.3 : 1.0);
      }
      emisiones.add(aLogProbabilidades(puntuaciones, temperatura: ajustes.temperatura));
    }

    final camino = Viterbi(
      numeroDeClases: vocabulario.length,
      permanencia: ajustes.permanencia,
    ).decodificar(emisiones);

    final tramos = <Tramo>[];
    for (var f = 0; f < camino.length; f++) {
      final inicio = croma.tiempoDe(f);
      final fin = croma.tiempoDe(f + 1);
      tramos.add(Tramo(inicio, fin, vocabulario[camino[f]].etiqueta));
    }

    // Sin esto la salida tendría un tramo por cada 93 ms.
    final fusionados = fusionarContiguos(tramos);
    // Silenciar el índice cuando no se usa evita un aviso del analizador y
    // deja claro que el silencio ya está dentro del vocabulario.
    assert(indiceDeSilencio >= 0, 'el vocabulario debe incluir N');
    return fusionados;
  }

  /// Analiza un WAV del disco.
  List<Tramo> analizarArchivo(String ruta) => analizar(leerWavDeArchivo(ruta));

  /// Energía media por frame, en la misma rejilla que el cromagrama.
  Float64List _energiaPorFrame(Cromagrama croma, Audio audio) {
    final a = remuestrear(audio, ajustes.cromagrama.frecuencia);
    final salida = Float64List(croma.largo);
    final ventana = ajustes.cromagrama.tamanoDeVentana;
    for (var f = 0; f < croma.largo; f++) {
      final inicio = f * ajustes.cromagrama.salto;
      var suma = 0.0;
      var cuenta = 0;
      for (var i = inicio; i < inicio + ventana && i < a.muestras.length; i++) {
        suma += a.muestras[i].abs();
        cuenta++;
      }
      salida[f] = cuenta == 0 ? 0.0 : suma / cuenta;
    }
    return salida;
  }
}
