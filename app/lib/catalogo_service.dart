import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:motor_acordes/motor_acordes.dart';

/// Una voicing concreta del catálogo, con el nombre de acorde que le
/// corresponde — lo que el catálogo de more-than-modes llama "calidad" y
/// "raíz" por separado.
class EjercicioVoicing {
  final String calidad;
  final String raiz;
  final Voicing voicing;

  const EjercicioVoicing({
    required this.calidad,
    required this.raiz,
    required this.voicing,
  });

  String get nombre => '$raiz $calidad';
}

/// Carga `assets/chord_database.json` — el mismo catálogo simbólico de
/// more-than-modes, copiado tal cual— y lo aplana a una lista de voicings
/// tocables. No hace falta el audio del catálogo aquí: para verificar contra
/// un objetivo conocido basta la digitación, `cromaDeVoicing` calcula la
/// plantilla a partir de las notas MIDI, no de una grabación.
class CatalogoService {
  List<EjercicioVoicing>? _cache;

  Future<List<EjercicioVoicing>> cargar() async {
    final cache = _cache;
    if (cache != null) return cache;

    final texto = await rootBundle.loadString('assets/chord_database.json');
    final json = jsonDecode(texto) as Map<String, dynamic>;

    final salida = <EjercicioVoicing>[];
    for (final calidadEntry in json.entries) {
      final porRaiz = calidadEntry.value as Map<String, dynamic>;
      for (final raizEntry in porRaiz.entries) {
        for (final forma in (raizEntry.value as List).cast<String>()) {
          final Voicing voicing;
          try {
            voicing = Voicing.deTexto(forma);
          } catch (_) {
            continue; // forma ilegible: se salta, no rompe el catálogo entero
          }
          if (voicing.esSilencio) continue;
          salida.add(EjercicioVoicing(
            calidad: calidadEntry.key,
            raiz: raizEntry.key,
            voicing: voicing,
          ));
        }
      }
    }

    _cache = salida;
    return salida;
  }
}
