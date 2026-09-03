import 'dart:io';

import 'harte.dart';

/// Un tramo de la canción con su etiqueta de acorde.
class Tramo {
  final double inicio;
  final double fin;
  final String etiqueta;

  const Tramo(this.inicio, this.fin, this.etiqueta);

  double get duracion => fin - inicio;

  Acorde get acorde => interpretarAcorde(etiqueta);

  @override
  String toString() =>
      '${inicio.toStringAsFixed(3)}\t${fin.toStringAsFixed(3)}\t$etiqueta';
}

/// Lee un archivo `.lab`: una línea por tramo, `inicio fin etiqueta`,
/// separados por tabulador o espacios.
///
/// Es el mismo formato que exporta Audacity con *Exportar etiquetas*, así que
/// se puede etiquetar ahí y traer el archivo tal cual.
List<Tramo> leerLab(String contenido) {
  final tramos = <Tramo>[];
  var numeroDeLinea = 0;

  for (final linea in contenido.split('\n')) {
    numeroDeLinea++;
    final limpia = linea.trim();
    if (limpia.isEmpty || limpia.startsWith('#')) continue;

    final partes = limpia.split(RegExp(r'[\s\t]+'));
    if (partes.length < 3) {
      throw FormatException(
          'Línea $numeroDeLinea: hacen falta inicio, fin y etiqueta → "$limpia"');
    }

    final inicio = double.tryParse(partes[0]);
    final fin = double.tryParse(partes[1]);
    if (inicio == null || fin == null) {
      throw FormatException('Línea $numeroDeLinea: tiempos no numéricos → "$limpia"');
    }
    if (fin < inicio) {
      throw FormatException('Línea $numeroDeLinea: el fin va antes del inicio → "$limpia"');
    }

    // La etiqueta puede llevar espacios; se junta lo que quede.
    final etiqueta = partes.sublist(2).join(' ');
    tramos.add(Tramo(inicio, fin, etiqueta));
  }

  tramos.sort((a, b) => a.inicio.compareTo(b.inicio));
  return tramos;
}

List<Tramo> leerLabDeArchivo(String ruta) => leerLab(File(ruta).readAsStringSync());

String escribirLab(List<Tramo> tramos) => '${tramos.map((t) => t.toString()).join('\n')}\n';

/// Junta tramos contiguos con la misma etiqueta. El motor produce un tramo por
/// frame, y sin esto el `.lab` de salida tendría miles de líneas.
List<Tramo> fusionarContiguos(List<Tramo> tramos) {
  if (tramos.isEmpty) return const [];
  final salida = <Tramo>[];
  var inicio = tramos.first.inicio;
  var fin = tramos.first.fin;
  var etiqueta = tramos.first.etiqueta;

  for (var i = 1; i < tramos.length; i++) {
    final t = tramos[i];
    // 1 ms de tolerancia: los bordes vienen de aritmética en coma flotante.
    final pegado = (t.inicio - fin).abs() < 1e-3;
    if (t.etiqueta == etiqueta && pegado) {
      fin = t.fin;
    } else {
      salida.add(Tramo(inicio, fin, etiqueta));
      inicio = t.inicio;
      fin = t.fin;
      etiqueta = t.etiqueta;
    }
  }
  salida.add(Tramo(inicio, fin, etiqueta));
  return salida;
}

/// Rellena con `N` los huecos y recorta al rango pedido, de modo que la
/// anotación cubra `[desde, hasta]` sin saltos.
///
/// Hace falta antes de puntuar: si la estimación no cubre un trozo que la
/// referencia sí etiqueta, ese trozo cuenta como fallo, no desaparece.
List<Tramo> rellenarYRecortar(List<Tramo> tramos, double desde, double hasta) {
  final salida = <Tramo>[];
  var cursor = desde;

  for (final t in tramos) {
    if (t.fin <= desde || t.inicio >= hasta) continue;
    final inicio = t.inicio < desde ? desde : t.inicio;
    final fin = t.fin > hasta ? hasta : t.fin;
    if (fin <= inicio) continue;
    if (inicio > cursor + 1e-9) salida.add(Tramo(cursor, inicio, 'N'));
    salida.add(Tramo(inicio, fin, t.etiqueta));
    cursor = fin;
  }

  if (cursor < hasta - 1e-9) salida.add(Tramo(cursor, hasta, 'N'));
  return salida;
}
