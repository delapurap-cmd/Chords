import 'package:motor_acordes/motor_acordes.dart';
import 'package:test/test.dart';

void main() {
  group('interpretar la notación', () {
    test('acorde mayor sin abreviatura', () {
      final a = interpretarAcorde('C');
      expect(a.fundamental, 0);
      expect(a.intervalos, {0, 4, 7});
      expect(a.bajo, 0);
    });

    test('abreviatura explícita', () {
      expect(interpretarAcorde('C:maj').intervalos, {0, 4, 7});
      expect(interpretarAcorde('A:min').intervalos, {0, 3, 7});
      expect(interpretarAcorde('G:7').intervalos, {0, 4, 7, 10});
      expect(interpretarAcorde('F:maj7').intervalos, {0, 4, 7, 11});
      expect(interpretarAcorde('D:min7').intervalos, {0, 3, 7, 10});
    });

    test('alteraciones en la fundamental', () {
      expect(interpretarAcorde('C#:maj').fundamental, 1);
      expect(interpretarAcorde('Db:maj').fundamental, 1);
      expect(interpretarAcorde('B#:maj').fundamental, 0, reason: 'si# envuelve a do');
      expect(interpretarAcorde('Cb:maj').fundamental, 11, reason: 'dob envuelve a si');
    });

    test('enarmónicos distintos son el mismo acorde', () {
      final a = interpretarAcorde('F#:min7');
      final b = interpretarAcorde('Gb:min7');
      expect(a.fundamental, b.fundamental);
      expect(a.intervalos, b.intervalos);
    });

    test('inversiones', () {
      final a = interpretarAcorde('G:7/3');
      expect(a.fundamental, 7);
      expect(a.bajo, 4, reason: 'la tercera son 4 semitonos');
      expect(a.claseDelBajo, 11, reason: 'sol + tercera mayor = si');

      final b = interpretarAcorde('C:maj/5');
      expect(b.claseDelBajo, 7);
    });

    test('grados añadidos y quitados', () {
      final anadido = interpretarAcorde('C:maj(9)');
      expect(anadido.intervalos, containsAll({0, 4, 7, 2}));

      final quitado = interpretarAcorde('A:min7(*5)');
      expect(quitado.intervalos.contains(7), isFalse,
          reason: 'la quinta se ha quitado con *5');
      expect(quitado.intervalos, containsAll({0, 3, 10}));
    });

    test('silencio y desconocido', () {
      expect(interpretarAcorde('N').esSilencio, isTrue);
      expect(interpretarAcorde('X').esDesconocido, isTrue);
    });

    test('el bajo entra en el acorde aunque no estuviera', () {
      // Do mayor con la séptima menor en el bajo: el si bemol suena.
      final a = interpretarAcorde('C:maj/b7');
      expect(a.intervalos.contains(10), isTrue);
    });

    test('las etiquetas rotas avisan en vez de fallar en silencio', () {
      expect(() => interpretarAcorde('H:maj'), throwsA(isA<ErrorDeNotacion>()));
      expect(() => interpretarAcorde('C:inventado'), throwsA(isA<ErrorDeNotacion>()));
      expect(() => interpretarAcorde(''), throwsA(isA<ErrorDeNotacion>()));
    });
  });

  group('calidades', () {
    test('tríadas', () {
      expect(calidadDeTriada(interpretarAcorde('C:maj')), CalidadTriada.mayor);
      expect(calidadDeTriada(interpretarAcorde('C:min')), CalidadTriada.menor);
      expect(calidadDeTriada(interpretarAcorde('C:dim')), CalidadTriada.disminuida);
      expect(calidadDeTriada(interpretarAcorde('C:aug')), CalidadTriada.aumentada);
      expect(calidadDeTriada(interpretarAcorde('C:sus4')), CalidadTriada.sus4);
      expect(calidadDeTriada(interpretarAcorde('C:sus2')), CalidadTriada.sus2);
    });

    test('una séptima no cambia la tríada', () {
      expect(calidadDeTriada(interpretarAcorde('C:maj7')), CalidadTriada.mayor);
      expect(calidadDeTriada(interpretarAcorde('C:min7')), CalidadTriada.menor);
      expect(calidadDeTriada(interpretarAcorde('C:7')), CalidadTriada.mayor);
    });

    test('séptimas', () {
      expect(calidadDeSeptima(interpretarAcorde('C:maj7')), CalidadSeptima.mayor7);
      expect(calidadDeSeptima(interpretarAcorde('C:min7')), CalidadSeptima.menor7);
      expect(calidadDeSeptima(interpretarAcorde('C:7')), CalidadSeptima.dominante7);
      expect(calidadDeSeptima(interpretarAcorde('C:dim7')), CalidadSeptima.disminuida7);
      expect(calidadDeSeptima(interpretarAcorde('C:hdim7')), CalidadSeptima.semidisminuida7);
      expect(calidadDeSeptima(interpretarAcorde('C:minmaj7')), CalidadSeptima.menorMayor7);
      expect(calidadDeSeptima(interpretarAcorde('C:maj')), CalidadSeptima.mayor);
    });

    test('una novena añadida no altera la calidad de séptima', () {
      expect(calidadDeSeptima(interpretarAcorde('C:maj7(9)')), CalidadSeptima.mayor7);
      expect(calidadDeSeptima(interpretarAcorde('C:9')), CalidadSeptima.dominante7);
    });
  });
}
