/// Notación de acordes de Harte, que es la que usan todos los corpus
/// etiquetados del campo (Isophonics, Billboard, RWC) y la que vamos a usar
/// nosotros en los `.lab`.
///
/// Ejemplos válidos:
///   `N`            sin acorde (silencio, percusión sola)
///   `X`            no se sabe
///   `C`            do mayor (sin abreviatura = maj)
///   `C:maj`        do mayor
///   `Db:min7`      re bemol menor séptima
///   `G:7/3`        sol séptima de dominante con la tercera en el bajo
///   `F#:maj(9)`    fa sostenido mayor con novena añadida
///   `A:min7(*5)`   la menor séptima sin la quinta
library;

/// Un acorde ya interpretado: fundamental, intervalos y bajo.
///
/// Los intervalos van en semitonos **relativos a la fundamental**, y el 0
/// (la propia fundamental) está siempre incluido salvo que se quite con `*1`.
class Acorde {
  /// Clase de altura de la fundamental, 0 = do … 11 = si. -1 si no hay acorde.
  final int fundamental;

  /// Semitonos sobre la fundamental. Para do mayor: {0, 4, 7}.
  final Set<int> intervalos;

  /// Intervalo del bajo sobre la fundamental. 0 = estado fundamental.
  final int bajo;

  /// `N` en la notación: no suena ningún acorde.
  final bool esSilencio;

  /// `X` en la notación: el que etiquetó no supo qué era. No se puntúa.
  final bool esDesconocido;

  const Acorde({
    required this.fundamental,
    required this.intervalos,
    this.bajo = 0,
    this.esSilencio = false,
    this.esDesconocido = false,
  });

  static const Acorde silencio =
      Acorde(fundamental: -1, intervalos: {}, esSilencio: true);
  static const Acorde desconocido =
      Acorde(fundamental: -1, intervalos: {}, esDesconocido: true);

  /// Clase de altura absoluta del bajo, para comparar inversiones.
  int get claseDelBajo => esSilencio ? -1 : (fundamental + bajo) % 12;

  @override
  String toString() {
    if (esSilencio) return 'N';
    if (esDesconocido) return 'X';
    final lista = intervalos.toList()..sort();
    return '${_nombresDeClase[fundamental]}:${lista.join(",")}'
        '${bajo == 0 ? "" : "/$bajo"}';
  }
}

const _nombresDeClase = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];

const Map<String, int> _clasePorLetra = {
  'C': 0, 'D': 2, 'E': 4, 'F': 5, 'G': 7, 'A': 9, 'B': 11,
};

/// Semitonos de cada grado de la escala mayor. El 8 y el 10 no son estándar
/// en Harte pero aparecen en corpus reales, así que se aceptan.
const Map<int, int> _semitonosPorGrado = {
  1: 0, 2: 2, 3: 4, 4: 5, 5: 7, 6: 9, 7: 11,
  8: 12, 9: 14, 10: 16, 11: 17, 12: 19, 13: 21,
};

/// Abreviaturas de Harte con sus intervalos. La fundamental (0) va incluida.
const Map<String, Set<int>> abreviaturas = {
  '': {0, 4, 7}, // sin abreviatura = mayor
  'maj': {0, 4, 7},
  'min': {0, 3, 7},
  'dim': {0, 3, 6},
  'aug': {0, 4, 8},
  'maj7': {0, 4, 7, 11},
  'min7': {0, 3, 7, 10},
  '7': {0, 4, 7, 10},
  'dim7': {0, 3, 6, 9},
  'hdim7': {0, 3, 6, 10},
  'minmaj7': {0, 3, 7, 11},
  'maj6': {0, 4, 7, 9},
  '6': {0, 4, 7, 9},
  'min6': {0, 3, 7, 9},
  '9': {0, 4, 7, 10, 2},
  'maj9': {0, 4, 7, 11, 2},
  'min9': {0, 3, 7, 10, 2},
  '11': {0, 4, 7, 10, 2, 5},
  'maj11': {0, 4, 7, 11, 2, 5},
  'min11': {0, 3, 7, 10, 2, 5},
  '13': {0, 4, 7, 10, 2, 5, 9},
  'maj13': {0, 4, 7, 11, 2, 5, 9},
  'min13': {0, 3, 7, 10, 2, 5, 9},
  'sus2': {0, 2, 7},
  'sus4': {0, 5, 7},
  '5': {0, 7}, // power chord, frecuente en guitarra
  '1': {0},
};

/// Error de notación con el texto que lo provocó, para que el corpus se pueda
/// depurar en vez de fallar en silencio.
class ErrorDeNotacion implements Exception {
  final String texto;
  final String motivo;
  ErrorDeNotacion(this.texto, this.motivo);
  @override
  String toString() => 'Acorde inválido "$texto": $motivo';
}

/// Convierte un grado de Harte (`3`, `b7`, `#11`, `bb7`) a semitonos.
int semitonosDeGrado(String grado) {
  var i = 0;
  var alteracion = 0;
  while (i < grado.length && (grado[i] == 'b' || grado[i] == '#')) {
    alteracion += grado[i] == 'b' ? -1 : 1;
    i++;
  }
  final numero = int.tryParse(grado.substring(i));
  if (numero == null || !_semitonosPorGrado.containsKey(numero)) {
    throw ErrorDeNotacion(grado, 'grado no reconocido');
  }
  return (_semitonosPorGrado[numero]! + alteracion) % 12;
}

/// Interpreta una etiqueta de acorde en notación Harte.
Acorde interpretarAcorde(String texto) {
  final t = texto.trim();
  if (t.isEmpty) throw ErrorDeNotacion(texto, 'etiqueta vacía');
  if (t == 'N' || t == 'n') return Acorde.silencio;
  if (t == 'X' || t == 'x') return Acorde.desconocido;

  // ── Bajo ────────────────────────────────────────────────────────────────
  var cuerpo = t;
  var bajo = 0;
  final barra = cuerpo.indexOf('/');
  if (barra >= 0) {
    final textoBajo = cuerpo.substring(barra + 1);
    cuerpo = cuerpo.substring(0, barra);
    bajo = semitonosDeGrado(textoBajo);
  }

  // ── Fundamental ─────────────────────────────────────────────────────────
  final letra = cuerpo.isEmpty ? '' : cuerpo[0].toUpperCase();
  if (!_clasePorLetra.containsKey(letra)) {
    throw ErrorDeNotacion(texto, 'fundamental no reconocida');
  }
  var fundamental = _clasePorLetra[letra]!;
  var i = 1;
  while (i < cuerpo.length && (cuerpo[i] == 'b' || cuerpo[i] == '#')) {
    fundamental += cuerpo[i] == 'b' ? -1 : 1;
    i++;
  }
  fundamental = (fundamental % 12 + 12) % 12;
  cuerpo = cuerpo.substring(i);

  // ── Abreviatura y grados entre paréntesis ───────────────────────────────
  var abreviatura = '';
  var extras = <String>[];
  if (cuerpo.startsWith(':')) {
    cuerpo = cuerpo.substring(1);
    final abre = cuerpo.indexOf('(');
    if (abre >= 0) {
      final cierra = cuerpo.indexOf(')');
      if (cierra < abre) throw ErrorDeNotacion(texto, 'paréntesis sin cerrar');
      abreviatura = cuerpo.substring(0, abre);
      extras = cuerpo
          .substring(abre + 1, cierra)
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
    } else {
      abreviatura = cuerpo;
    }
  } else if (cuerpo.isNotEmpty) {
    // `C(9)` sin dos puntos: Harte lo permite.
    if (cuerpo.startsWith('(') && cuerpo.endsWith(')')) {
      extras = cuerpo
          .substring(1, cuerpo.length - 1)
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
    } else {
      throw ErrorDeNotacion(texto, 'no se entiende "$cuerpo"');
    }
  }

  if (!abreviaturas.containsKey(abreviatura)) {
    throw ErrorDeNotacion(texto, 'abreviatura "$abreviatura" desconocida');
  }
  final intervalos = <int>{...abreviaturas[abreviatura]!};

  // Los grados con `*` se quitan; el resto se añaden.
  for (final extra in extras) {
    if (extra.startsWith('*')) {
      intervalos.remove(semitonosDeGrado(extra.substring(1)));
    } else {
      intervalos.add(semitonosDeGrado(extra));
    }
  }

  // El bajo suena, así que forma parte del acorde aunque no estuviera.
  if (bajo != 0) intervalos.add(bajo);

  return Acorde(fundamental: fundamental, intervalos: intervalos, bajo: bajo);
}

// ═══════════════════════════════════════════════════════════════════════════
// CALIDADES
// ═══════════════════════════════════════════════════════════════════════════

/// Calidad de la tríada, ignorando séptimas y tensiones.
enum CalidadTriada { mayor, menor, disminuida, aumentada, sus2, sus4, otra }

/// Calidad hasta la séptima. Es el nivel al que se mide "acordes complejos".
enum CalidadSeptima {
  mayor, menor, disminuida, aumentada, sus2, sus4,
  mayor7, menor7, dominante7, disminuida7, semidisminuida7, menorMayor7,
  otra,
}

CalidadTriada calidadDeTriada(Acorde a) {
  if (a.esSilencio || a.esDesconocido) return CalidadTriada.otra;
  final iv = a.intervalos;
  final tieneMenor = iv.contains(3);
  final tieneMayor = iv.contains(4);
  final quintaJusta = iv.contains(7);
  final quintaBaja = iv.contains(6);
  final quintaAlta = iv.contains(8);

  if (tieneMayor && quintaJusta) return CalidadTriada.mayor;
  if (tieneMenor && quintaJusta) return CalidadTriada.menor;
  if (tieneMenor && quintaBaja && !quintaJusta) return CalidadTriada.disminuida;
  if (tieneMayor && quintaAlta && !quintaJusta) return CalidadTriada.aumentada;
  if (!tieneMenor && !tieneMayor) {
    if (iv.contains(5) && quintaJusta) return CalidadTriada.sus4;
    if (iv.contains(2) && quintaJusta) return CalidadTriada.sus2;
  }
  return CalidadTriada.otra;
}

CalidadSeptima calidadDeSeptima(Acorde a) {
  if (a.esSilencio || a.esDesconocido) return CalidadSeptima.otra;
  final triada = calidadDeTriada(a);
  final iv = a.intervalos;
  final septimaMenor = iv.contains(10);
  final septimaMayor = iv.contains(11);
  final sextaODisminuida = iv.contains(9);

  switch (triada) {
    case CalidadTriada.mayor:
      if (septimaMayor) return CalidadSeptima.mayor7;
      if (septimaMenor) return CalidadSeptima.dominante7;
      return CalidadSeptima.mayor;
    case CalidadTriada.menor:
      if (septimaMenor) return CalidadSeptima.menor7;
      if (septimaMayor) return CalidadSeptima.menorMayor7;
      return CalidadSeptima.menor;
    case CalidadTriada.disminuida:
      if (septimaMenor) return CalidadSeptima.semidisminuida7;
      if (sextaODisminuida) return CalidadSeptima.disminuida7;
      return CalidadSeptima.disminuida;
    case CalidadTriada.aumentada:
      return CalidadSeptima.aumentada;
    case CalidadTriada.sus2:
      return CalidadSeptima.sus2;
    case CalidadTriada.sus4:
      return CalidadSeptima.sus4;
    case CalidadTriada.otra:
      return CalidadSeptima.otra;
  }
}
