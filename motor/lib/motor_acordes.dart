/// Motor de reconocimiento de acordes.
///
/// Dart puro, sin una sola importación de Flutter. Eso es a propósito: así el
/// mismo código corre bajo `dart test` contra el corpus en segundos y se
/// embarca tal cual en la app, sin que lo que se mide y lo que se envía
/// puedan separarse.
library motor_acordes;

export 'src/cromagrama.dart';
export 'src/evaluacion.dart';
export 'src/fft.dart';
export 'src/harte.dart';
export 'src/lab.dart';
export 'src/motor.dart';
export 'src/plantillas.dart';
export 'src/verificacion.dart';
export 'src/viterbi.dart';
export 'src/voicing.dart';
export 'src/wav.dart';
