import 'package:flutter/material.dart';

import '../catalogo_service.dart';
import '../progresion_service.dart';
import 'progresion_en_vivo_page.dart';

/// Elegí qué progresión tocar en vivo: la de ejemplo, o el catálogo entero.
class ProgresionMenuPage extends StatelessWidget {
  const ProgresionMenuPage({super.key});

  @override
  Widget build(BuildContext context) {
    final catalogo = CatalogoService();
    final progresiones = ProgresionService(catalogo);

    return Scaffold(
      appBar: AppBar(title: const Text('Progresiones')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _TarjetaProgresion(
              titulo: 'A Maj7 – D#dim7 – C#m7 – Bm7 – E7',
              subtitulo: 'I – vi – ii – V con un disminuido de paso',
              cargar: progresiones.progresionEjemplo,
            ),
            const SizedBox(height: 12),
            _TarjetaProgresion(
              titulo: 'Catálogo completo',
              subtitulo: 'Las 12 mayores, las 12 menores, las 12 disminuidas y las 12 de séptima',
              cargar: progresiones.progresionCatalogoCompleto,
            ),
          ],
        ),
      ),
    );
  }
}

class _TarjetaProgresion extends StatelessWidget {
  final String titulo;
  final String subtitulo;
  final Future<List<EjercicioVoicing>> Function() cargar;

  const _TarjetaProgresion({
    required this.titulo,
    required this.subtitulo,
    required this.cargar,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text(titulo),
        subtitle: Text(subtitulo),
        trailing: const Icon(Icons.play_arrow),
        onTap: () async {
          final pasos = await cargar();
          if (!context.mounted) return;
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ProgresionEnVivoPage(titulo: titulo, pasos: pasos),
            ),
          );
        },
      ),
    );
  }
}
