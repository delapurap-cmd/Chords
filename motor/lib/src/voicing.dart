import 'dart:typed_data';

/// Una voicing de guitarra en la misma notación que `chord_database.json` de
/// more-than-modes: un traste por cuerda, -1 si la cuerda no suena.
///
/// Índice 0 = mi agudo, índice 5 = mi grave — el mismo orden que usa la app
/// (confirmado contra el propio JSON: do mayor es "0,1,0,2,3,-1", que con
/// esta convención da mi=0, si=1, sol=0, re=2, la=3, mi grave mudo).
class Voicing {
  final List<int> trastes; // longitud 6, -1 = cuerda muda

  const Voicing(this.trastes) : assert(trastes.length == 6);

  /// Interpreta "0,1,0,2,3,-1" tal cual sale del catálogo.
  factory Voicing.deTexto(String texto) =>
      Voicing(texto.split(',').map(int.parse).toList(growable: false));

  /// Índices de cuerda con nota activa, en el orden en que se puntea el
  /// catálogo (0..5, agudo→grave). El sintetizador reordena según el
  /// rasgueo; esto es solo "quién suena".
  List<int> get cuerdasActivas =>
      [for (var i = 0; i < 6; i++) if (trastes[i] != -1) i];

  bool get esSilencio => cuerdasActivas.isEmpty;
}

/// MIDI de la cuerda al aire, índice 0 (mi agudo) a 5 (mi grave). Afinación
/// estándar E-A-D-G-B-e.
const List<int> midiCuerdaAlAire = [64, 59, 55, 50, 45, 40];

/// Nota MIDI que suena en una cuerda a un traste dado.
int notaMidi(int cuerda, int traste) => midiCuerdaAlAire[cuerda] + traste;

/// Las notas MIDI que suenan en una voicing, una por cuerda activa.
List<int> notasMidiDeVoicing(Voicing v) => [
      for (final c in v.cuerdasActivas) notaMidi(c, v.trastes[c]),
    ];

/// Plantilla de croma esperada para una voicing concreta: no la calidad del
/// acorde en abstracto (eso ya lo cubre `plantillas.dart`), sino las notas
/// exactas que esa digitación produce, dobles incluidas. Un mi que suena en
/// dos cuerdas pesa el doble que uno que solo suena en una — así debería
/// verse también en el croma capturado por el micrófono.
Float64List cromaDeVoicing(Voicing v) {
  final croma = Float64List(12);
  for (final midi in notasMidiDeVoicing(v)) {
    croma[midi % 12] += 1.0;
  }
  var maximo = 0.0;
  for (final x in croma) {
    if (x > maximo) maximo = x;
  }
  if (maximo > 1e-12) {
    for (var i = 0; i < 12; i++) {
      croma[i] /= maximo;
    }
  }
  return croma;
}
