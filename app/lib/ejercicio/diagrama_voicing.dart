import 'package:flutter/material.dart';
import 'package:motor_acordes/motor_acordes.dart';

/// Dibuja una voicing como diagrama de acorde: 6 cuerdas, X para mudas, un
/// círculo hueco para al aire, un punto para cada traste pisado.
///
/// La ventana de trastes se centra en dónde de verdad se toca la forma, no
/// siempre en el traste 1 — el catálogo trae formas que suben mástil arriba
/// (p.ej. "20,20,21,22,22,20"), y empezar el dibujo en el traste 1 las dejaría
/// fuera de cuadro.
class DiagramaVoicing extends StatelessWidget {
  final Voicing voicing;

  const DiagramaVoicing({super.key, required this.voicing});

  @override
  Widget build(BuildContext context) {
    final activos = voicing.trastes.where((f) => f > 0);
    final minFret = activos.isEmpty
        ? 1
        : activos.reduce((a, b) => a < b ? a : b);
    final maxFret = activos.isEmpty
        ? 1
        : activos.reduce((a, b) => a > b ? a : b);
    final baseFret = minFret <= 1 ? 1 : minFret;
    final span = (maxFret - baseFret + 1).clamp(4, 6);

    return AspectRatio(
      aspectRatio: 0.72,
      child: CustomPaint(
        painter: _DiagramaPainter(voicing.trastes, baseFret, span),
      ),
    );
  }
}

class _DiagramaPainter extends CustomPainter {
  /// Índice 0 = mi agudo .. 5 = mi grave, igual que el resto del motor.
  final List<int> trastes;
  final int baseFret;
  final int span;

  static const _color = Color(0xFFD4C46A);

  _DiagramaPainter(this.trastes, this.baseFret, this.span);

  @override
  void paint(Canvas canvas, Size size) {
    const margenSup = 28.0;
    const margenLat = 20.0;
    const margenInf = 12.0;
    final anchoGrid = size.width - margenLat * 2;
    final altoGrid = size.height - margenSup - margenInf;
    final pasoCuerda = anchoGrid / 5;
    final pasoTraste = altoGrid / span;

    final lineaFina = Paint()
      ..color = Colors.white38
      ..strokeWidth = 1.2;

    // Cuerdas verticales: izquierda = grave (índice 5), derecha = aguda (0).
    for (var i = 0; i < 6; i++) {
      final x = margenLat + i * pasoCuerda;
      canvas.drawLine(
        Offset(x, margenSup),
        Offset(x, margenSup + altoGrid),
        lineaFina,
      );
    }

    // Trastes horizontales; el borde superior es más grueso solo si es la
    // cejuela de verdad (traste 0, no el corte de una ventana desplazada).
    for (var t = 0; t <= span; t++) {
      final y = margenSup + t * pasoTraste;
      final esCejuela = baseFret == 1 && t == 0;
      canvas.drawLine(
        Offset(margenLat, y),
        Offset(margenLat + anchoGrid, y),
        Paint()
          ..color = Colors.white38
          ..strokeWidth = esCejuela ? 3.0 : 1.0,
      );
    }

    if (baseFret > 1) {
      _dibujarTexto(
        canvas,
        '${baseFret}fr',
        margenLat + anchoGrid + 4,
        margenSup + pasoTraste * 0.5,
        alinearIzquierda: true,
      );
    }

    for (var col = 0; col < 6; col++) {
      // Columna 0 = grave = trastes[5]; columna 5 = aguda = trastes[0].
      final traste = trastes[5 - col];
      final x = margenLat + col * pasoCuerda;

      if (traste == -1) {
        _dibujarTexto(canvas, 'X', x, margenSup - 14);
        continue;
      }
      if (traste == 0) {
        canvas.drawCircle(
          Offset(x, margenSup - 14),
          5,
          Paint()
            ..color = Colors.white70
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );
        continue;
      }
      final posicion = traste - baseFret;
      if (posicion < 0 || posicion >= span) continue;
      final y = margenSup + (posicion + 0.5) * pasoTraste;
      canvas.drawCircle(Offset(x, y), pasoCuerda * 0.32, Paint()..color = _color);
    }
  }

  void _dibujarTexto(
    Canvas canvas,
    String texto,
    double x,
    double y, {
    bool alinearIzquierda = false,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: texto,
        style: const TextStyle(
          color: Colors.white70,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final dx = alinearIzquierda ? x : x - tp.width / 2;
    tp.paint(canvas, Offset(dx, y - tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _DiagramaPainter oldDelegate) =>
      oldDelegate.trastes != trastes ||
      oldDelegate.baseFret != baseFret ||
      oldDelegate.span != span;
}
