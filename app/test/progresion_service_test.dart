import 'package:flutter_test/flutter_test.dart';

import 'package:chords_app/catalogo_service.dart';
import 'package:chords_app/progresion_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final progresiones = ProgresionService(CatalogoService());

  test('la progresión de ejemplo trae los 5 acordes en orden', () async {
    final pasos = await progresiones.progresionEjemplo();
    expect(pasos.map((p) => p.nombre).toList(), [
      'A Maj7',
      'D# dim7',
      'C# m7',
      'B m7',
      'E 7',
    ]);
  });

  test('el catálogo completo trae las 48 combinaciones sin repetir', () async {
    final pasos = await progresiones.progresionCatalogoCompleto();
    expect(pasos.length, 48);
    final nombres = pasos.map((p) => p.nombre).toSet();
    expect(nombres.length, 48, reason: 'no debería haber acordes repetidos');
  });
}
