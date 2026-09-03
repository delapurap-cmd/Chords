import 'dart:typed_data';

import 'package:flutter_audio_capture/flutter_audio_capture.dart';
import 'package:motor_acordes/motor_acordes.dart';

/// Captura de micrófono directa a un [Audio] del motor.
///
/// No pasa por un WAV en disco: aquí no hace falta guardar nada, solo
/// verificar en el momento, así que las muestras se acumulan en memoria y se
/// devuelven tal cual las entiende el motor.
///
/// Dos modos, según [segundosVentana]:
/// - sin dar (por defecto): graba la toma entera, sin límite — lo que usa el
///   ejercicio manual de "grabar y parar".
/// - con [segundosVentana]: recorta a una ventana móvil de esa duración y
///   llama a [onVentana] en cada bloque — lo que hace falta para verificar en
///   vivo mientras se sigue tocando, sin parar de grabar entre acorde y
///   acorde.
class CapturadorMic {
  final FlutterAudioCapture _captura = FlutterAudioCapture();
  final int frecuenciaPedida;
  final int? _maxMuestras;
  final List<double> _muestras = [];
  bool _grabando = false;
  double? _frecuenciaReal;

  /// Pico de amplitud del último bloque recibido, para un medidor de nivel.
  void Function(double energia)? onAmplitud;

  /// Ventana móvil de audio acumulada hasta ahora. Solo se dispara si se
  /// construyó con [segundosVentana].
  void Function(Audio ventana)? onVentana;

  CapturadorMic({this.frecuenciaPedida = 48000, double? segundosVentana})
      : _maxMuestras = segundosVentana == null
            ? null
            : (frecuenciaPedida * segundosVentana).round();

  Future<void> iniciar() => _captura.init();

  Future<void> grabar() async {
    if (_grabando) return;
    _muestras.clear();
    _frecuenciaReal = null;
    await _captura.start(
      _escuchar,
      (Object error) {},
      sampleRate: frecuenciaPedida,
      bufferSize: 4096,
    );
    _grabando = true;
  }

  void _escuchar(Float32List bloque) {
    if (bloque.isEmpty) return;
    _frecuenciaReal = _captura.actualSampleRate;

    var pico = 0.0;
    for (final valor in bloque) {
      final muestra = valor > 1.0 ? 1.0 : (valor < -1.0 ? -1.0 : valor);
      _muestras.add(muestra);
      final abs = muestra.abs();
      if (abs > pico) pico = abs;
    }

    final tope = _maxMuestras;
    if (tope != null) {
      final exceso = _muestras.length - tope;
      if (exceso > 0) _muestras.removeRange(0, exceso);
    }

    onAmplitud?.call(pico);
    final ventana = onVentana;
    if (ventana != null) {
      final frecuencia = (_frecuenciaReal ?? frecuenciaPedida.toDouble()).round();
      ventana(Audio(Float64List.fromList(_muestras), frecuencia));
    }
  }

  /// Detiene la captura y devuelve lo grabado como [Audio]. La frecuencia es
  /// la que de verdad usó el dispositivo, no necesariamente [frecuenciaPedida]
  /// — algunos micrófonos la ignoran.
  Future<Audio> detener() async {
    onAmplitud = null;
    onVentana = null;
    if (!_grabando) return Audio(Float64List(0), frecuenciaPedida);
    try {
      await _captura.stop();
    } catch (_) {}
    _grabando = false;
    final frecuencia = (_frecuenciaReal ?? frecuenciaPedida.toDouble()).round();
    return Audio(Float64List.fromList(_muestras), frecuencia);
  }

  void dispose() {
    onAmplitud = null;
    onVentana = null;
    if (_grabando) {
      _grabando = false;
      _captura.stop().catchError((_) {});
    }
  }
}
