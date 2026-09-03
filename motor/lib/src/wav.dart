import 'dart:io';
import 'dart:typed_data';

/// Audio ya decodificado: muestras mono en coma flotante, entre -1 y 1.
class Audio {
  final Float64List muestras;
  final int frecuencia;

  const Audio(this.muestras, this.frecuencia);

  double get duracion => muestras.length / frecuencia;
}

/// Lee un WAV PCM y lo devuelve en mono.
///
/// El MVP trabaja solo con WAV a propósito: decodificar mp3 en Dart es un
/// pozo, y el corpus se convierte una sola vez. Lo de leer mp3 y m4a en el
/// móvil es una tarea aparte, con código nativo en las dos plataformas.
Audio leerWav(Uint8List bytes) {
  if (bytes.length < 44) throw FormatException('WAV demasiado corto');
  final datos = ByteData.sublistView(bytes);

  String etiqueta(int desde) =>
      String.fromCharCodes(bytes.sublist(desde, desde + 4));

  if (etiqueta(0) != 'RIFF' || etiqueta(8) != 'WAVE') {
    throw FormatException('No es un WAV: falta la cabecera RIFF/WAVE');
  }

  var formato = -1;
  var canales = 0;
  var frecuencia = 0;
  var bitsPorMuestra = 0;
  var inicioDatos = -1;
  var tamanoDatos = 0;

  // Los WAV traen los bloques en orden variable, así que se recorren.
  var cursor = 12;
  while (cursor + 8 <= bytes.length) {
    final nombre = etiqueta(cursor);
    final tamano = datos.getUint32(cursor + 4, Endian.little);
    final cuerpo = cursor + 8;

    if (nombre == 'fmt ') {
      formato = datos.getUint16(cuerpo, Endian.little);
      canales = datos.getUint16(cuerpo + 2, Endian.little);
      frecuencia = datos.getUint32(cuerpo + 4, Endian.little);
      bitsPorMuestra = datos.getUint16(cuerpo + 14, Endian.little);
    } else if (nombre == 'data') {
      inicioDatos = cuerpo;
      tamanoDatos = tamano;
    }

    // Los bloques se alinean a par.
    cursor = cuerpo + tamano + (tamano.isOdd ? 1 : 0);
  }

  if (inicioDatos < 0 || canales == 0 || frecuencia == 0) {
    throw FormatException('WAV incompleto: falta fmt o data');
  }

  final finDatos = (inicioDatos + tamanoDatos).clamp(0, bytes.length);
  final bytesPorMuestra = bitsPorMuestra ~/ 8;
  if (bytesPorMuestra == 0) throw FormatException('bitsPorMuestra inválido');

  final totalMuestras = (finDatos - inicioDatos) ~/ (bytesPorMuestra * canales);
  final mono = Float64List(totalMuestras);

  for (var i = 0; i < totalMuestras; i++) {
    var suma = 0.0;
    for (var c = 0; c < canales; c++) {
      final pos = inicioDatos + (i * canales + c) * bytesPorMuestra;
      suma += _muestra(datos, pos, formato, bitsPorMuestra);
    }
    mono[i] = suma / canales;
  }

  return Audio(mono, frecuencia);
}

double _muestra(ByteData d, int pos, int formato, int bits) {
  // 1 = PCM entero, 3 = coma flotante IEEE.
  if (formato == 3) {
    if (bits == 32) return d.getFloat32(pos, Endian.little);
    if (bits == 64) return d.getFloat64(pos, Endian.little);
    throw FormatException('WAV flotante de $bits bits no soportado');
  }
  switch (bits) {
    case 8:
      return (d.getUint8(pos) - 128) / 128.0; // 8 bits va sin signo
    case 16:
      return d.getInt16(pos, Endian.little) / 32768.0;
    case 24:
      final b0 = d.getUint8(pos);
      final b1 = d.getUint8(pos + 1);
      final b2 = d.getInt8(pos + 2); // el más alto lleva el signo
      return ((b2 << 16) | (b1 << 8) | b0) / 8388608.0;
    case 32:
      return d.getInt32(pos, Endian.little) / 2147483648.0;
    default:
      throw FormatException('WAV PCM de $bits bits no soportado');
  }
}

Audio leerWavDeArchivo(String ruta) => leerWav(File(ruta).readAsBytesSync());

/// Escribe PCM 16 bits mono. Es lo único que hace falta: nada en este
/// proyecto necesita estéreo ni más resolución que esa.
Uint8List escribirWav(Audio audio) {
  final n = audio.muestras.length;
  final datos = ByteData(44 + n * 2);
  void texto(int pos, String s) {
    for (var i = 0; i < s.length; i++) {
      datos.setUint8(pos + i, s.codeUnitAt(i));
    }
  }

  texto(0, 'RIFF');
  datos.setUint32(4, 36 + n * 2, Endian.little);
  texto(8, 'WAVE');
  texto(12, 'fmt ');
  datos.setUint32(16, 16, Endian.little);
  datos.setUint16(20, 1, Endian.little); // PCM entero
  datos.setUint16(22, 1, Endian.little); // mono
  datos.setUint32(24, audio.frecuencia, Endian.little);
  datos.setUint32(28, audio.frecuencia * 2, Endian.little);
  datos.setUint16(32, 2, Endian.little);
  datos.setUint16(34, 16, Endian.little);
  texto(36, 'data');
  datos.setUint32(40, n * 2, Endian.little);
  for (var i = 0; i < n; i++) {
    final m = (audio.muestras[i] * 32767).round().clamp(-32768, 32767);
    datos.setInt16(44 + i * 2, m, Endian.little);
  }
  return datos.buffer.asUint8List();
}

void escribirWavAArchivo(Audio audio, String ruta) =>
    File(ruta).writeAsBytesSync(escribirWav(audio));

/// Remuestrea por interpolación lineal.
///
/// Para reconocer acordes basta: solo interesa la zona por debajo de 2 kHz,
/// muy lejos de Nyquist a 11 kHz, así que el aliasing que introduce no llega
/// a la banda que se analiza.
Audio remuestrear(Audio audio, int destino) {
  if (audio.frecuencia == destino) return audio;
  final razon = audio.frecuencia / destino;
  final total = (audio.muestras.length / razon).floor();
  final salida = Float64List(total);
  for (var i = 0; i < total; i++) {
    final pos = i * razon;
    final j = pos.floor();
    final resto = pos - j;
    final a = audio.muestras[j];
    final b = j + 1 < audio.muestras.length ? audio.muestras[j + 1] : a;
    salida[i] = a + (b - a) * resto;
  }
  return Audio(salida, destino);
}
