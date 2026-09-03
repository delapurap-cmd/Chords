import 'catalogo_service.dart';

/// Progresiones de acordes armadas a partir del catálogo, para practicarlas
/// en fila en vez de acorde suelto.
///
/// Para cada raíz+calidad se usa siempre la primera forma del catálogo: es la
/// de posición más grave, la más práctica para tocar en una progresión — las
/// formas de más arriba en el mástil quedan para el ejercicio de una sola
/// voicing.
class ProgresionService {
  final CatalogoService _catalogo;

  const ProgresionService(this._catalogo);

  static const _raices = [
    'C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B',
  ];

  EjercicioVoicing _buscar(List<EjercicioVoicing> lista, String raiz, String calidad) {
    for (final e in lista) {
      if (e.raiz == raiz && e.calidad == calidad) return e;
    }
    throw StateError('no está "$raiz $calidad" en el catálogo');
  }

  /// A Maj7 → D#dim7 → C#m7 → Bm7 → E7: un I – vi – ii – V en la mayor, con
  /// un disminuido de paso entre el I y el vi.
  Future<List<EjercicioVoicing>> progresionEjemplo() async {
    final lista = await _catalogo.cargar();
    return [
      _buscar(lista, 'A', 'Maj7'),
      _buscar(lista, 'D#', 'dim7'),
      _buscar(lista, 'C#', 'm7'),
      _buscar(lista, 'B', 'm7'),
      _buscar(lista, 'E', '7'),
    ];
  }

  /// Las 12 mayores, después las 12 menores, después las 12 disminuidas,
  /// después las 12 de séptima dominante: 48 acordes en fila.
  Future<List<EjercicioVoicing>> progresionCatalogoCompleto() async {
    final lista = await _catalogo.cargar();
    const bloques = ['Mayor', 'Menor', 'dim7', '7'];
    final pasos = <EjercicioVoicing>[];
    for (final calidad in bloques) {
      for (final raiz in _raices) {
        try {
          pasos.add(_buscar(lista, raiz, calidad));
        } catch (_) {
          continue; // esa combinación no está en el catálogo: se salta
        }
      }
    }
    return pasos;
  }
}
