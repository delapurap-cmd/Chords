import 'package:motor_acordes/motor_acordes.dart';
import 'package:test/test.dart';

void main() {
  group('lectura de .lab', () {
    test('acepta tabuladores y espacios', () {
      final t = leerLab('0.0\t2.5\tC:maj\n2.5 5.0 A:min\n');
      expect(t.length, 2);
      expect(t[0].etiqueta, 'C:maj');
      expect(t[1].inicio, 2.5);
    });

    test('ignora comentarios y líneas vacías', () {
      final t = leerLab('# canción de prueba\n\n0.0 1.0 N\n');
      expect(t.length, 1);
    });

    test('protesta si faltan columnas o los tiempos no son números', () {
      expect(() => leerLab('0.0 C:maj\n'), throwsFormatException);
      expect(() => leerLab('inicio fin C:maj\n'), throwsFormatException);
      expect(() => leerLab('5.0 1.0 C:maj\n'), throwsFormatException,
          reason: 'el fin no puede ir antes del inicio');
    });

    test('fusiona tramos contiguos iguales', () {
      final t = fusionarContiguos([
        const Tramo(0.0, 1.0, 'C:maj'),
        const Tramo(1.0, 2.0, 'C:maj'),
        const Tramo(2.0, 3.0, 'A:min'),
      ]);
      expect(t.length, 2);
      expect(t[0].fin, 3.0 - 1.0);
      expect(t[1].etiqueta, 'A:min');
    });

    test('rellena huecos con N', () {
      final t = rellenarYRecortar([const Tramo(1.0, 2.0, 'C:maj')], 0.0, 3.0);
      expect(t.length, 3);
      expect(t[0].etiqueta, 'N');
      expect(t[1].etiqueta, 'C:maj');
      expect(t[2].etiqueta, 'N');
    });
  });

  group('WCSR', () {
    test('una estimación idéntica saca 1,0', () {
      final ref = leerLab('0.0 2.0 C:maj\n2.0 4.0 A:min\n');
      final r = evaluar(ref, ref);
      expect(r[Nivel.mayorMenor]!.wcsr, 1.0);
      expect(r[Nivel.fundamental]!.wcsr, 1.0);
    });

    test('acertar la mitad del tiempo da 0,5', () {
      final ref = leerLab('0.0 2.0 C:maj\n2.0 4.0 A:min\n');
      final est = leerLab('0.0 2.0 C:maj\n2.0 4.0 F:maj\n');
      final r = evaluar(ref, est);
      expect(r[Nivel.mayorMenor]!.wcsr, closeTo(0.5, 1e-9));
    });

    test('pondera por duración, no por número de acordes', () {
      // Nueve segundos bien y uno mal: 0,9 aunque sean un acorde cada uno.
      final ref = leerLab('0.0 9.0 C:maj\n9.0 10.0 A:min\n');
      final est = leerLab('0.0 9.0 C:maj\n9.0 10.0 F:maj\n');
      final r = evaluar(ref, est);
      expect(r[Nivel.mayorMenor]!.wcsr, closeTo(0.9, 1e-9));
    });

    test('los bordes desalineados se cruzan bien', () {
      final ref = leerLab('0.0 4.0 C:maj\n');
      // El motor cambia a destiempo en el segundo 3.
      final est = leerLab('0.0 3.0 C:maj\n3.0 4.0 A:min\n');
      final r = evaluar(ref, est);
      expect(r[Nivel.mayorMenor]!.wcsr, closeTo(0.75, 1e-9));
    });

    test('acertar la fundamental y fallar la calidad separa los dos niveles', () {
      final ref = leerLab('0.0 4.0 C:maj\n');
      final est = leerLab('0.0 4.0 C:min\n');
      final r = evaluar(ref, est);
      expect(r[Nivel.fundamental]!.wcsr, 1.0, reason: 'la fundamental es la misma');
      expect(r[Nivel.mayorMenor]!.wcsr, 0.0, reason: 'la calidad no');
    });

    test('lo que cae fuera del vocabulario no cuenta como fallo', () {
      // A nivel mayor/menor, un sus4 no es una pregunta que ese nivel haga.
      final ref = leerLab('0.0 2.0 C:maj\n2.0 4.0 C:sus4\n');
      final est = leerLab('0.0 4.0 C:maj\n');
      final r = evaluar(ref, est);
      expect(r[Nivel.mayorMenor]!.wcsr, 1.0,
          reason: 'los dos segundos de sus4 se descartan, no se suspenden');
      expect(r[Nivel.mayorMenor]!.segundosFuera, closeTo(2.0, 1e-9));
      expect(r[Nivel.mayorMenor]!.cobertura, closeTo(0.5, 1e-9));
    });

    test('a nivel de séptimas sí se distingue maj de maj7', () {
      final ref = leerLab('0.0 4.0 C:maj7\n');
      final est = leerLab('0.0 4.0 C:maj\n');
      final r = evaluar(ref, est);
      expect(r[Nivel.mayorMenor]!.wcsr, 1.0,
          reason: 'a mayor/menor, un maj7 se reduce a mayor y acierta');
      expect(r[Nivel.septimas]!.wcsr, 0.0,
          reason: 'a séptimas, confundir maj7 con maj es un fallo');
    });

    test('el silencio se puntúa', () {
      final ref = leerLab('0.0 2.0 N\n2.0 4.0 C:maj\n');
      final bien = leerLab('0.0 2.0 N\n2.0 4.0 C:maj\n');
      final mal = leerLab('0.0 4.0 C:maj\n');
      expect(evaluar(ref, bien)[Nivel.mayorMenor]!.wcsr, 1.0);
      expect(evaluar(ref, mal)[Nivel.mayorMenor]!.wcsr, closeTo(0.5, 1e-9),
          reason: 'inventar un acorde donde no lo hay es un fallo');
    });

    test('el tiempo que la estimación no cubre cuenta como fallo', () {
      final ref = leerLab('0.0 4.0 C:maj\n');
      final est = leerLab('0.0 2.0 C:maj\n'); // se queda a medias
      final r = evaluar(ref, est);
      expect(r[Nivel.mayorMenor]!.wcsr, closeTo(0.5, 1e-9),
          reason: 'no etiquetar no puede salir gratis');
    });

    test('las inversiones solo importan en los niveles que las piden', () {
      final ref = leerLab('0.0 4.0 C:maj/3\n');
      final est = leerLab('0.0 4.0 C:maj\n');
      final r = evaluar(ref, est);
      expect(r[Nivel.mayorMenor]!.wcsr, 1.0);
      expect(r[Nivel.mayorMenorConInversion]!.wcsr, 0.0);
    });

    test('agregar pondera las canciones por su duración', () {
      final corta = evaluar(leerLab('0.0 1.0 C:maj\n'), leerLab('0.0 1.0 F:maj\n'));
      final larga = evaluar(leerLab('0.0 9.0 C:maj\n'), leerLab('0.0 9.0 C:maj\n'));
      final total = agregar([corta, larga]);
      expect(total[Nivel.mayorMenor]!.wcsr, closeTo(0.9, 1e-9));
    });
  });

  group('confusiones', () {
    test('anota con qué se confunde cada acorde', () {
      final ref = leerLab('0.0 3.0 C:maj7\n');
      final est = leerLab('0.0 3.0 C:maj\n');
      final c = Confusiones();
      evaluar(ref, est, confusiones: c);
      final peores = c.peores(5);
      expect(peores.first.referencia, 'C:maj7');
      expect(peores.first.estimado, 'C:maj');
      expect(peores.first.segundos, closeTo(3.0, 1e-9));
    });
  });
}
