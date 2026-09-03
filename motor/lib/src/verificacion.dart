import 'dart:math' as math;
import 'dart:typed_data';

import 'cromagrama.dart';
import 'voicing.dart';
import 'wav.dart';

/// Modo de verificación: no "¿qué acorde es esto?" sobre las 61 clases
/// abiertas de `plantillas.dart`, sino "¿esto es la voicing X?" contra un
/// objetivo ya conocido — que es la pregunta real para un ejercicio de
/// more-than-modes, donde la app sabe de antemano qué digitación se pide.
/// Verificar contra un objetivo conocido es mucho más fácil que reconocer en
/// abierto, y es justo lo que hace falta aquí.
///
/// La plantilla de cada voicing es simbólica —se calcula a partir de las
/// notas MIDI reales de cada cuerda y traste, no de una grabación—, así que
/// no importa que el catálogo de more-than-modes sintetice el sonido
/// desplazando el tono de una muestra: el pitch-shift no cambia qué nota
/// suena, solo el timbre, y aquí se compara altura, no timbre.

/// Resultado de comparar una captura contra una voicing objetivo.
class ResultadoVerificacion {
  /// Similitud coseno entre el croma capturado y el esperado, 0 a 1.
  final double puntuacion;

  /// `puntuacion >= umbral` del verificador que lo produjo.
  final bool acierto;

  /// Clases de altura que la voicing pedía y no sonaron con fuerza.
  final List<int> clasesFaltantes;

  /// Clases de altura que sonaron fuerte sin que la voicing las pidiera.
  final List<int> clasesSobrantes;

  const ResultadoVerificacion({
    required this.puntuacion,
    required this.acierto,
    required this.clasesFaltantes,
    required this.clasesSobrantes,
  });
}

/// Compara audio capturado contra una o varias voicings conocidas.
class VerificadorDeVoicing {
  /// Puntuación mínima para dar la voicing por acertada.
  final double umbral;

  /// Frames por debajo de esta energía se tratan como silencio y se excluyen
  /// del promedio — así el silencio de antes del rasgueo, o el que queda
  /// después de que la cuerda se apaga, no diluye la lectura.
  final double umbralSilencio;

  /// Por debajo de esto una clase de altura se considera "no suena", tanto
  /// para decidir qué falta como qué sobra.
  final double umbralClase;

  const VerificadorDeVoicing({
    this.umbral = 0.85,
    this.umbralSilencio = 0.015,
    this.umbralClase = 0.3,
  });

  ResultadoVerificacion verificar(Audio capturado, Voicing objetivo) {
    final promedio = _cromaPromedioActivo(capturado);
    final esperado = cromaDeVoicing(objetivo);
    final puntuacion = _coseno(promedio, esperado);

    final faltantes = <int>[];
    final sobrantes = <int>[];
    for (var i = 0; i < 12; i++) {
      final seEspera = esperado[i] > umbralClase;
      final sueneFuerte = promedio[i] > umbralClase;
      if (seEspera && !sueneFuerte) faltantes.add(i);
      if (!seEspera && sueneFuerte) sobrantes.add(i);
    }

    return ResultadoVerificacion(
      puntuacion: puntuacion,
      acierto: puntuacion >= umbral,
      clasesFaltantes: faltantes,
      clasesSobrantes: sobrantes,
    );
  }

  /// Para un ejercicio de "¿cuál de estas tocaste?": puntúa la misma captura
  /// contra varios candidatos y los devuelve de mejor a peor.
  List<MapEntry<Voicing, double>> rankear(
    Audio capturado,
    List<Voicing> candidatos,
  ) {
    final promedio = _cromaPromedioActivo(capturado);
    final resultados = [
      for (final v in candidatos) MapEntry(v, _coseno(promedio, cromaDeVoicing(v))),
    ];
    resultados.sort((a, b) => b.value.compareTo(a.value));
    return resultados;
  }

  /// Promedia el croma solo en los frames con energía por encima del umbral
  /// de silencio — evita que la calma de antes o después del rasgueo tire la
  /// media hacia cero.
  Float64List _cromaPromedioActivo(Audio audio) {
    const ajustes = AjustesDeCromagrama();
    final croma = calcularCromagrama(audio, ajustes: ajustes);
    if (croma.largo == 0) return Float64List(12);

    final energias = _energiaPorFrame(audio, ajustes);
    final promedio = Float64List(12);
    var frames = 0;
    for (var f = 0; f < croma.largo; f++) {
      if (energias[f] < umbralSilencio) continue;
      for (var i = 0; i < 12; i++) {
        promedio[i] += croma.frames[f][i];
      }
      frames++;
    }
    if (frames == 0) return Float64List(12); // todo era silencio
    for (var i = 0; i < 12; i++) {
      promedio[i] /= frames;
    }
    return promedio;
  }

  Float64List _energiaPorFrame(Audio audio, AjustesDeCromagrama ajustes) {
    final a = remuestrear(audio, ajustes.frecuencia);
    final salto = ajustes.salto;
    final ventana = ajustes.tamanoDeVentana;
    final totalFrames =
        a.muestras.length < ventana ? 0 : (a.muestras.length - ventana) ~/ salto + 1;
    final salida = Float64List(totalFrames);
    for (var f = 0; f < totalFrames; f++) {
      final inicio = f * salto;
      var suma = 0.0;
      for (var i = inicio; i < inicio + ventana; i++) {
        suma += a.muestras[i].abs();
      }
      salida[f] = suma / ventana;
    }
    return salida;
  }
}

/// Coseno propio y no el de `plantillas.dart`: aquella asume que la
/// plantilla ya llega con norma L2 unitaria, y `cromaDeVoicing` normaliza
/// por el máximo, no por la norma — mezclar las dos habría dado una
/// puntuación mal escalada, no un coseno de verdad entre 0 y 1.
double _coseno(Float64List a, Float64List b) {
  var punto = 0.0, normaA = 0.0, normaB = 0.0;
  for (var i = 0; i < 12; i++) {
    punto += a[i] * b[i];
    normaA += a[i] * a[i];
    normaB += b[i] * b[i];
  }
  if (normaA < 1e-12 || normaB < 1e-12) return 0.0;
  return punto / (math.sqrt(normaA) * math.sqrt(normaB));
}
