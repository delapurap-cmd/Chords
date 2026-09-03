import 'dart:typed_data';

import 'package:motor_acordes/motor_acordes.dart';
import 'package:test/test.dart';

import 'motor_test.dart' show sintetizar;

void main() {
  // Do mayor abierto: mi-do-sol-mi-do, cuerda grave muda.
  final cMayor = Voicing.deTexto('0,1,0,2,3,-1');
  // Sol mayor abierto: sol-si-sol-re-si-sol.
  final gMayor = Voicing.deTexto('3,0,0,0,2,3');
  // La menor abierto: mi-do-la-mi-la, cuerda grave muda.
  final aMenor = Voicing.deTexto('0,1,2,2,0,-1');

  group('cromaDeVoicing', () {
    test('do mayor enciende do, mi y sol, con do y mi al doble que sol', () {
      final croma = cromaDeVoicing(cMayor);
      expect(croma[0], closeTo(1.0, 1e-9)); // do, suena en dos cuerdas
      expect(croma[4], closeTo(1.0, 1e-9)); // mi, suena en dos cuerdas
      expect(croma[7], closeTo(0.5, 1e-9)); // sol, suena en una
      for (final i in [1, 2, 3, 5, 6, 8, 9, 10, 11]) {
        expect(croma[i], 0.0, reason: 'clase $i no debería sonar');
      }
    });
  });

  group('VerificadorDeVoicing.verificar', () {
    test('acepta una captura limpia de la voicing pedida', () {
      final captura = sintetizar([
        (midis: [48, 52, 55], segundos: 2.0), // do, mi, sol
      ]);
      final resultado = const VerificadorDeVoicing().verificar(captura, cMayor);
      expect(resultado.acierto, isTrue,
          reason: 'puntuación ${resultado.puntuacion}');
      expect(resultado.clasesFaltantes, isEmpty);
    });

    test('rechaza una captura de un acorde distinto', () {
      final captura = sintetizar([
        (midis: [43, 47, 50], segundos: 2.0), // sol, si, re
      ]);
      final resultado = const VerificadorDeVoicing().verificar(captura, cMayor);
      expect(resultado.acierto, isFalse,
          reason: 'puntuación ${resultado.puntuacion}');
      expect(resultado.clasesFaltantes, containsAll([0, 4])); // do y mi
      expect(resultado.clasesSobrantes, isNotEmpty);
    });

    test('el silencio no acierta ninguna voicing', () {
      final captura = Audio(Float64List((22050 * 1.0).round()), 22050);
      final resultado = const VerificadorDeVoicing().verificar(captura, cMayor);
      expect(resultado.acierto, isFalse);
      expect(resultado.puntuacion, 0.0);
    });
  });

  group('VerificadorDeVoicing.rankear', () {
    test('pone primera la voicing que de verdad sonó', () {
      final captura = sintetizar([
        (midis: [48, 52, 55], segundos: 2.0), // do, mi, sol
      ]);
      final resultados =
          const VerificadorDeVoicing().rankear(captura, [gMayor, aMenor, cMayor]);
      expect(resultados.first.key, same(cMayor));
      expect(resultados.first.value, greaterThan(resultados[1].value));
    });
  });
}
