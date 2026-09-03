import 'dart:async';

import 'package:flutter/material.dart';
import 'package:motor_acordes/motor_acordes.dart';

import '../captura/capturador_mic.dart';
import '../catalogo_service.dart';
import '../ejercicio/diagrama_voicing.dart';
import '../permiso_mic.dart';

/// Escucha continua, sin grabar-y-esperar: el micrófono queda abierto toda la
/// progresión y cada acorde avanza solo apenas se sostiene lo bastante fuerte
/// y limpio — como tocarla de verdad, no como una serie de exámenes sueltos.
class ProgresionEnVivoPage extends StatefulWidget {
  final String titulo;
  final List<EjercicioVoicing> pasos;

  const ProgresionEnVivoPage({super.key, required this.titulo, required this.pasos});

  @override
  State<ProgresionEnVivoPage> createState() => _ProgresionEnVivoPageState();
}

/// Cuántas verificaciones seguidas por encima del umbral hacen falta para
/// avanzar — evita que un rasgueo de transición dispare el acierto a medio
/// camino entre dos acordes.
const _aciertosParaAvanzar = 2;
const _periodoVerificacion = Duration(milliseconds: 200);
const _pausaTrasAcierto = Duration(milliseconds: 600);

/// El verificador promedia el croma de toda la ventana móvil: cuanto más
/// larga, más tarda en "vaciarse" el acorde anterior cuando cambiás de uno a
/// otro. 0.6s todavía deja un par de cuadros del cromagrama (que ya de por sí
/// usa ventanas de ~370ms) para promediar, pero reacciona bastante más rápido
/// que un segundo y medio — clave para un acorde staccato, que dura poco.
const _segundosVentana = 0.6;

class _ProgresionEnVivoPageState extends State<ProgresionEnVivoPage> {
  final _capturador = CapturadorMic(segundosVentana: _segundosVentana);

  /// Umbral de aceptación, ajustable en vivo con la perilla — el 0.85 por
  /// defecto de VerificadorDeVoicing salió calibrado contra el catálogo
  /// sintético, no contra guitarra real ni contra todos los micrófonos.
  double _umbral = 0.85;

  Audio? _ventanaActual;
  Timer? _temporizador;
  int _indice = 0;
  double _amplitud = 0.0;
  ResultadoVerificacion? _ultimoResultado;
  int _aciertosSeguidos = 0;
  bool _avanzando = false;
  bool _escuchando = false;
  bool _completado = false;
  String? _error;

  EjercicioVoicing? get _actual =>
      _indice < widget.pasos.length ? widget.pasos[_indice] : null;

  @override
  void initState() {
    super.initState();
    _iniciar();
  }

  Future<void> _iniciar() async {
    if (widget.pasos.isEmpty) {
      setState(() => _error = 'Esta progresión no tiene acordes para tocar.');
      return;
    }
    final permitido = await pedirPermisoMic(context);
    if (!permitido || !mounted) return;

    try {
      await _capturador.iniciar();
      _capturador.onAmplitud = (e) {
        if (mounted) setState(() => _amplitud = e);
      };
      _capturador.onVentana = (audio) => _ventanaActual = audio;
      await _capturador.grabar();
      if (!mounted) return;
      setState(() => _escuchando = true);
      _temporizador = Timer.periodic(_periodoVerificacion, (_) => _verificarPaso());
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  void _verificarPaso() {
    final actual = _actual;
    final ventana = _ventanaActual;
    if (_avanzando || actual == null || ventana == null) return;

    final resultado = VerificadorDeVoicing(umbral: _umbral).verificar(ventana, actual.voicing);
    if (resultado.acierto) {
      _aciertosSeguidos++;
    } else {
      _aciertosSeguidos = 0;
    }

    if (!mounted) return;
    setState(() => _ultimoResultado = resultado);

    if (_aciertosSeguidos >= _aciertosParaAvanzar) {
      _avanzar();
    }
  }

  void _avanzar() {
    _avanzando = true;
    _aciertosSeguidos = 0;
    Future.delayed(_pausaTrasAcierto, () {
      if (!mounted) return;
      setState(() {
        _avanzando = false;
        _ultimoResultado = null;
        if (_indice + 1 < widget.pasos.length) {
          _indice++;
        } else {
          _completado = true;
        }
      });
    });
  }

  Future<void> _reiniciar() async {
    setState(() {
      _indice = 0;
      _completado = false;
      _ultimoResultado = null;
      _aciertosSeguidos = 0;
      _avanzando = false;
    });
  }

  @override
  void dispose() {
    _temporizador?.cancel();
    _capturador.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.titulo)),
      body: SafeArea(child: _cuerpo(context)),
    );
  }

  Widget _cuerpo(BuildContext context) {
    if (_error != null) {
      return Center(child: Text('No se pudo escuchar: $_error'));
    }
    if (!_escuchando) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_completado) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.emoji_events, size: 64, color: Color(0xFFD4C46A)),
            const SizedBox(height: 12),
            Text('¡Progresión completa!', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 24),
            ElevatedButton(onPressed: _reiniciar, child: const Text('Otra vez')),
          ],
        ),
      );
    }

    final actual = _actual!;
    final acierto = _avanzando || (_ultimoResultado?.acierto ?? false);
    final puntuacion = _ultimoResultado?.puntuacion ?? 0.0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        children: [
          Text(
            '${_indice + 1} / ${widget.pasos.length}',
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: 8),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: Text(
              actual.nombre,
              key: ValueKey(_indice),
              style: Theme.of(context).textTheme.headlineMedium,
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 16),
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: acierto ? Colors.greenAccent : Colors.white24,
                width: 3,
              ),
            ),
            padding: const EdgeInsets.all(8),
            child: SizedBox(
              width: 200,
              child: DiagramaVoicing(voicing: actual.voicing),
            ),
          ),
          const SizedBox(height: 24),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: puntuacion.clamp(0.0, 1.0),
              minHeight: 6,
              color: acierto ? Colors.greenAccent : null,
            ),
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: _amplitud.clamp(0.0, 1.0),
              minHeight: 3,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Icon(Icons.tune, size: 18, color: Colors.white54),
              Expanded(
                child: Slider(
                  value: _umbral,
                  min: 0.5,
                  max: 0.97,
                  divisions: 47,
                  label: '${(_umbral * 100).round()}%',
                  onChanged: (v) => setState(() => _umbral = v),
                ),
              ),
              SizedBox(
                width: 44,
                child: Text(
                  '${(_umbral * 100).round()}%',
                  textAlign: TextAlign.end,
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ),
            ],
          ),
          const Spacer(),
        ],
      ),
    );
  }
}
