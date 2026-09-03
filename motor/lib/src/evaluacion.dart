import 'harte.dart';
import 'lab.dart';

/// Niveles de vocabulario a los que se puntúa, de menos a más exigente.
///
/// Son los mismos que usa `mir_eval.chord`, que es el evaluador estándar del
/// campo. Puntuar a varios niveles a la vez es lo que distingue "se equivoca
/// de fundamental" de "acierta la fundamental pero no la calidad": son fallos
/// con causas distintas y arreglos distintos.
enum Nivel {
  /// Solo la fundamental. Si esto falla, falla todo lo demás.
  fundamental,

  /// Mayor y menor. El nivel al que se publican casi todas las cifras.
  mayorMenor,

  /// Añade maj7, min7 y séptima de dominante. Aquí es donde se ve si el
  /// motor sirve de verdad para lo que quieres.
  septimas,

  /// Como [mayorMenor] pero exigiendo además el bajo correcto.
  mayorMenorConInversion,

  /// Como [septimas] pero exigiendo además el bajo correcto.
  septimasConInversion,
}

extension NombreDeNivel on Nivel {
  String get nombre => switch (this) {
        Nivel.fundamental => 'fundamental',
        Nivel.mayorMenor => 'mayor/menor',
        Nivel.septimas => 'séptimas',
        Nivel.mayorMenorConInversion => 'mayor/menor + inv',
        Nivel.septimasConInversion => 'séptimas + inv',
      };
}

/// Resultado de una comparación de un tramo.
enum Veredicto {
  acierto,
  fallo,

  /// El acorde de referencia queda fuera del vocabulario de este nivel, así
  /// que el tramo **no se cuenta**, ni a favor ni en contra.
  ///
  /// Esto es importante y se malinterpreta a menudo: si mides a nivel
  /// mayor/menor, un `C:maj9` de la referencia no es un fallo del motor, es
  /// una pregunta que ese nivel no hace. Contarlo como fallo hundiría la
  /// nota sin que signifique nada.
  fueraDeVocabulario,
}

const _calidadesMayorMenor = {CalidadTriada.mayor, CalidadTriada.menor};
const _calidadesSeptimas = {
  CalidadSeptima.mayor,
  CalidadSeptima.menor,
  CalidadSeptima.mayor7,
  CalidadSeptima.menor7,
  CalidadSeptima.dominante7,
};

/// Compara un acorde estimado contra el de referencia a un nivel dado.
Veredicto comparar(Acorde referencia, Acorde estimado, Nivel nivel) {
  // Lo que el anotador marcó como desconocido no se puntúa nunca.
  if (referencia.esDesconocido) return Veredicto.fueraDeVocabulario;

  // El silencio es parte del vocabulario en todos los niveles: acertar que
  // no hay acorde tiene mérito, y confundirlo con uno es un fallo real.
  if (referencia.esSilencio) {
    return estimado.esSilencio ? Veredicto.acierto : Veredicto.fallo;
  }
  if (estimado.esDesconocido) return Veredicto.fallo;

  switch (nivel) {
    case Nivel.fundamental:
      if (estimado.esSilencio) return Veredicto.fallo;
      return referencia.fundamental == estimado.fundamental
          ? Veredicto.acierto
          : Veredicto.fallo;

    case Nivel.mayorMenor:
    case Nivel.mayorMenorConInversion:
      final calidadRef = calidadDeTriada(referencia);
      if (!_calidadesMayorMenor.contains(calidadRef)) {
        return Veredicto.fueraDeVocabulario;
      }
      if (estimado.esSilencio) return Veredicto.fallo;
      final ok = referencia.fundamental == estimado.fundamental &&
          calidadRef == calidadDeTriada(estimado) &&
          (nivel == Nivel.mayorMenor ||
              referencia.claseDelBajo == estimado.claseDelBajo);
      return ok ? Veredicto.acierto : Veredicto.fallo;

    case Nivel.septimas:
    case Nivel.septimasConInversion:
      final calidadRef = calidadDeSeptima(referencia);
      if (!_calidadesSeptimas.contains(calidadRef)) {
        return Veredicto.fueraDeVocabulario;
      }
      if (estimado.esSilencio) return Veredicto.fallo;
      final ok = referencia.fundamental == estimado.fundamental &&
          calidadRef == calidadDeSeptima(estimado) &&
          (nivel == Nivel.septimas ||
              referencia.claseDelBajo == estimado.claseDelBajo);
      return ok ? Veredicto.acierto : Veredicto.fallo;
  }
}

/// Un tramo común a las dos anotaciones, con las dos etiquetas enfrentadas.
class TramoComparado {
  final double inicio;
  final double fin;
  final String referencia;
  final String estimado;

  const TramoComparado(this.inicio, this.fin, this.referencia, this.estimado);

  double get duracion => fin - inicio;
}

/// Parte las dos anotaciones por todos sus bordes, de modo que cada tramo
/// resultante tenga una sola etiqueta de referencia y una sola estimada.
List<TramoComparado> cruzar(List<Tramo> referencia, List<Tramo> estimado) {
  if (referencia.isEmpty) return const [];

  final desde = referencia.first.inicio;
  final hasta = referencia.last.fin;
  final ref = rellenarYRecortar(referencia, desde, hasta);
  final est = rellenarYRecortar(estimado, desde, hasta);

  final bordes = <double>{desde, hasta};
  for (final t in ref) {
    bordes.add(t.inicio);
    bordes.add(t.fin);
  }
  for (final t in est) {
    bordes.add(t.inicio);
    bordes.add(t.fin);
  }
  final ordenados = bordes.where((b) => b >= desde && b <= hasta).toList()..sort();

  String etiquetaEn(List<Tramo> tramos, double t) {
    for (final tr in tramos) {
      if (t >= tr.inicio - 1e-9 && t < tr.fin - 1e-9) return tr.etiqueta;
    }
    return 'N';
  }

  final salida = <TramoComparado>[];
  for (var i = 0; i < ordenados.length - 1; i++) {
    final a = ordenados[i];
    final b = ordenados[i + 1];
    if (b - a < 1e-6) continue; // borde duplicado
    salida.add(TramoComparado(a, b, etiquetaEn(ref, a), etiquetaEn(est, a)));
  }
  return salida;
}

/// Nota de una canción a un nivel: el WCSR y con qué se ha calculado.
class Puntuacion {
  final Nivel nivel;

  /// Segundos acertados.
  final double segundosAcertados;

  /// Segundos que sí se han puntuado (excluye los fuera de vocabulario).
  final double segundosPuntuados;

  /// Segundos descartados por caer fuera del vocabulario del nivel.
  final double segundosFuera;

  const Puntuacion({
    required this.nivel,
    required this.segundosAcertados,
    required this.segundosPuntuados,
    required this.segundosFuera,
  });

  /// *Weighted Chord Symbol Recall*: la proporción del tiempo que se etiqueta
  /// bien. Ponderado por duración, que es lo que se percibe al escuchar.
  double get wcsr => segundosPuntuados <= 0 ? 0.0 : segundosAcertados / segundosPuntuados;

  /// Qué parte de la canción ha quedado fuera de este nivel. Si es alta, la
  /// cifra de WCSR se apoya en poco tiempo y hay que mirarla con recelo.
  double get cobertura {
    final total = segundosPuntuados + segundosFuera;
    return total <= 0 ? 0.0 : segundosPuntuados / total;
  }
}

/// Cuántos segundos se ha confundido cada acorde con cada otro. Es el mapa
/// que dice *qué* arreglar, no solo si se va bien.
class Confusiones {
  final Map<String, Map<String, double>> segundos = {};

  void anotar(String referencia, String estimado, double duracion) {
    segundos.putIfAbsent(referencia, () => {});
    segundos[referencia]!.update(estimado, (v) => v + duracion,
        ifAbsent: () => duracion);
  }

  /// Las confusiones más caras en segundos, de peor a menos peor.
  List<({String referencia, String estimado, double segundos})> peores(int cuantas) {
    final lista = <({String referencia, String estimado, double segundos})>[];
    segundos.forEach((ref, mapa) {
      mapa.forEach((est, seg) {
        if (ref != est) lista.add((referencia: ref, estimado: est, segundos: seg));
      });
    });
    lista.sort((a, b) => b.segundos.compareTo(a.segundos));
    return lista.take(cuantas).toList();
  }
}

/// Evalúa una estimación contra su referencia a todos los niveles.
Map<Nivel, Puntuacion> evaluar(
  List<Tramo> referencia,
  List<Tramo> estimado, {
  Confusiones? confusiones,
  Nivel nivelDeConfusiones = Nivel.septimas,
}) {
  final cruce = cruzar(referencia, estimado);
  final resultado = <Nivel, Puntuacion>{};

  for (final nivel in Nivel.values) {
    var acertados = 0.0;
    var puntuados = 0.0;
    var fuera = 0.0;

    for (final tramo in cruce) {
      final Acorde ref;
      final Acorde est;
      try {
        ref = interpretarAcorde(tramo.referencia);
      } catch (_) {
        // Una etiqueta de referencia ilegible no puede puntuarse. Se descarta
        // en vez de reventar: es preferible una nota parcial a ninguna.
        fuera += tramo.duracion;
        continue;
      }
      try {
        est = interpretarAcorde(tramo.estimado);
      } catch (_) {
        // Que el MOTOR produzca basura sí es culpa suya: cuenta como fallo.
        puntuados += tramo.duracion;
        continue;
      }

      final veredicto = comparar(ref, est, nivel);
      switch (veredicto) {
        case Veredicto.acierto:
          acertados += tramo.duracion;
          puntuados += tramo.duracion;
        case Veredicto.fallo:
          puntuados += tramo.duracion;
        case Veredicto.fueraDeVocabulario:
          fuera += tramo.duracion;
      }

      if (confusiones != null && nivel == nivelDeConfusiones &&
          veredicto != Veredicto.fueraDeVocabulario) {
        confusiones.anotar(tramo.referencia, tramo.estimado, tramo.duracion);
      }
    }

    resultado[nivel] = Puntuacion(
      nivel: nivel,
      segundosAcertados: acertados,
      segundosPuntuados: puntuados,
      segundosFuera: fuera,
    );
  }

  return resultado;
}

/// Suma las puntuaciones de varias canciones ponderando por duración, que es
/// como se agrega en la literatura: una canción larga pesa más que una corta.
Map<Nivel, Puntuacion> agregar(Iterable<Map<Nivel, Puntuacion>> porCancion) {
  final resultado = <Nivel, Puntuacion>{};
  for (final nivel in Nivel.values) {
    var acertados = 0.0;
    var puntuados = 0.0;
    var fuera = 0.0;
    for (final cancion in porCancion) {
      final p = cancion[nivel];
      if (p == null) continue;
      acertados += p.segundosAcertados;
      puntuados += p.segundosPuntuados;
      fuera += p.segundosFuera;
    }
    resultado[nivel] = Puntuacion(
      nivel: nivel,
      segundosAcertados: acertados,
      segundosPuntuados: puntuados,
      segundosFuera: fuera,
    );
  }
  return resultado;
}
