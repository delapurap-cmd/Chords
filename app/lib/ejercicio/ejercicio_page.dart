import 'dart:math';

import 'package:flutter/material.dart';
import 'package:motor_acordes/motor_acordes.dart';

import '../captura/capturador_mic.dart';
import '../catalogo_service.dart';
import '../permiso_mic.dart';
import '../progresion/progresion_menu_page.dart';
import 'diagrama_voicing.dart';

enum _Estado { cargando, listo, grabando, evaluando }

/// La pantalla entera del v1: elegí una voicing al azar del catálogo, mostrá
/// cómo tocarla, grabá con el micrófono y decí si acertaste — comparando
/// contra un objetivo ya conocido, no reconociendo en abierto.
class EjercicioPage extends StatefulWidget {
  const EjercicioPage({super.key});

  @override
  State<EjercicioPage> createState() => _EjercicioPageState();
}

class _EjercicioPageState extends State<EjercicioPage> {
  final _catalogo = CatalogoService();
  final _capturador = CapturadorMic();
  final _random = Random();
  static const _verificador = VerificadorDeVoicing();

  List<EjercicioVoicing> _ejercicios = const [];
  EjercicioVoicing? _actual;
  _Estado _estado = _Estado.cargando;
  double _amplitud = 0.0;
  ResultadoVerificacion? _resultado;
  String? _error;

  @override
  void initState() {
    super.initState();
    _inicializar();
  }

  Future<void> _inicializar() async {
    try {
      final lista = await _catalogo.cargar();
      await _capturador.iniciar();
      if (!mounted) return;
      setState(() {
        _ejercicios = lista;
        _actual = lista[_random.nextInt(lista.length)];
        _estado = _Estado.listo;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    }
  }

  void _elegirOtra() {
    if (_ejercicios.isEmpty) return;
    setState(() {
      _actual = _ejercicios[_random.nextInt(_ejercicios.length)];
      _resultado = null;
      _estado = _Estado.listo;
    });
  }

  Future<void> _grabar() async {
    final permitido = await pedirPermisoMic(context);
    if (!permitido || !mounted) return;
    _capturador.onAmplitud = (e) {
      if (mounted) setState(() => _amplitud = e);
    };
    setState(() {
      _estado = _Estado.grabando;
      _resultado = null;
    });
    await _capturador.grabar();
  }

  Future<void> _detenerYVerificar() async {
    setState(() => _estado = _Estado.evaluando);
    final audio = await _capturador.detener();
    final resultado = _verificador.verificar(audio, _actual!.voicing);
    if (!mounted) return;
    setState(() {
      _resultado = resultado;
      _estado = _Estado.listo;
      _amplitud = 0.0;
    });
  }

  @override
  void dispose() {
    _capturador.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(body: Center(child: Text('No se pudo iniciar: $_error')));
    }
    if (_estado == _Estado.cargando || _actual == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final ejercicio = _actual!;
    final grabando = _estado == _Estado.grabando;
    final evaluando = _estado == _Estado.evaluando;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Chords — verificación'),
        actions: [
          IconButton(
            tooltip: 'Progresiones',
            icon: const Icon(Icons.queue_music),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ProgresionMenuPage()),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            children: [
              Text(
                ejercicio.nombre,
                style: Theme.of(context).textTheme.headlineMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: 220,
                child: DiagramaVoicing(voicing: ejercicio.voicing),
              ),
              const SizedBox(height: 24),
              if (grabando)
                Column(
                  children: [
                    const Text('Escuchando...'),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: _amplitud.clamp(0.0, 1.0),
                        minHeight: 8,
                      ),
                    ),
                  ],
                ),
              if (evaluando) const CircularProgressIndicator(),
              if (_resultado != null) _ResultadoView(resultado: _resultado!),
              const Spacer(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  OutlinedButton(
                    onPressed: grabando || evaluando ? null : _elegirOtra,
                    child: const Text('Otra'),
                  ),
                  if (!grabando)
                    ElevatedButton(
                      onPressed: evaluando ? null : _grabar,
                      child: const Text('Grabar'),
                    )
                  else
                    ElevatedButton(
                      onPressed: _detenerYVerificar,
                      child: const Text('Parar y verificar'),
                    ),
                ],
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

class _ResultadoView extends StatelessWidget {
  final ResultadoVerificacion resultado;

  const _ResultadoView({required this.resultado});

  static const _nombresNotas = [
    'Do', 'Do#', 'Re', 'Re#', 'Mi', 'Fa', 'Fa#', 'Sol', 'Sol#', 'La', 'La#', 'Si',
  ];

  static String _listar(List<int> clases) =>
      clases.map((i) => _nombresNotas[i]).join(', ');

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        children: [
          Text(
            resultado.acierto ? '¡Acertaste!' : 'Todavía no',
            style: TextStyle(
              color: resultado.acierto ? Colors.greenAccent : Colors.orangeAccent,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text('Puntuación: ${(resultado.puntuacion * 100).toStringAsFixed(0)}%'),
          if (resultado.clasesFaltantes.isNotEmpty)
            Text('Faltó: ${_listar(resultado.clasesFaltantes)}'),
          if (resultado.clasesSobrantes.isNotEmpty)
            Text('Sobró: ${_listar(resultado.clasesSobrantes)}'),
        ],
      ),
    );
  }
}
