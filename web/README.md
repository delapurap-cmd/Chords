# MTM AI Chord Studio — prueba móvil

`index.html` es un prototipo web independiente del motor Flutter/Dart existente. No modifica ni sustituye `motor/` o `app/`.

## Probar en Android

Descarga `web/index.html` desde GitHub (botón **Download raw file**), guárdalo como HTML y ábrelo con Chrome. La primera ejecución requiere Internet. Si Android no ofrece Chrome al abrir un archivo HTML local, se puede publicar esta carpeta mediante GitHub Pages u otro alojamiento estático HTTPS; **subir el archivo a GitHub no habilita GitHub Pages por sí mismo**.

Selecciona un MP3 corto (hasta 90 segundos; se recomiendan 30–60 s), pulsa **Analizar con IA**, corrige los acordes y exporta JSON o CSV. No sube audio a ningún servidor: navegador descarga el código y pesos del motor y ejecuta la inferencia en el dispositivo.

## Dependencias reales

- `@spotify/basic-pitch@1.0.1` como módulo ES desde `https://esm.sh/@spotify/basic-pitch@1.0.1?bundle` (incluye TensorFlow.js).
- Pesos TensorFlow.js desde `https://cdn.jsdelivr.net/npm/@spotify/basic-pitch@1.0.1/model/model.json` y su shard vinculado. **Son dependencias remotas**, no están embebidas en el HTML ni copiadas al repositorio.
- La API Web Audio del navegador decodifica MP3 y remuestrea el audio a 22.050 Hz mono.
- Basic Pitch es una red neuronal para detección de notas, **no un modelo de clasificación de acordes**. Posteriormente se agrupan sus activaciones en cromas de medio segundo y se comparan con patrones de 9 tipos de acorde; se suaviza la secuencia. Es un sistema híbrido experimental, no `lv-chordia` ni `ChordMini`.

Copyright 2022 Spotify AB; Basic Pitch se distribuye bajo Apache-2.0: https://github.com/spotify/basic-pitch-ts/blob/main/LICENSE . Para distribución final, conserva los avisos de terceros.

## Exportación

`JSON editor` guarda `format: mtm-chords-v1` y `chords: [{start,end,chord}]`; es un contrato propuesto, **no una integración ya terminada** con el editor de partituras. También exporta CSV y ChordPro.

## Límites y estado

El código se añadió al repositorio, pero **no se ha ejecutado una inferencia completa en un teléfono Android real**, ni se ha medido su precisión con canciones de referencia. La importación del CDN, disponibilidad del modelo y rendimiento móvil dependen de conexión, versión del navegador y memoria. El botón mostrará el error de carga o de inferencia sin fabricar resultados. La descarga de un HTML local puede estar restringida por algunas aplicaciones Android. El proyecto todavía requiere ensayo práctico antes de llamarlo producción.
