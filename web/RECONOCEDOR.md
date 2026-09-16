# Reconocedor de acordes — página y APK

`reconocedor.html` es el motor de `motor/` portado a JavaScript, en un solo
fichero. Se le da un MP3 o un WAV y devuelve el cifrado.

## Por qué no usa una red neuronal

`index.html` —el otro prototipo de esta carpeta— usa Basic Pitch de Spotify, y
para eso descarga la librería de `esm.sh` y los pesos de `jsdelivr` en cada
arranque. Funciona, pero invierte la premisa del repositorio, que está escrita
en negrita en el README raíz: **«100% sin conexión. Sin servidores. Sin APIs de
terceros. Lo que acabe en el móvil corre en el móvil.»**

Este va por el otro lado: **ni una petición a la red**. Todo lo que hace está en
el fichero. Los dos pueden convivir y compararse — de eso se trata.

## Qué hace, exactamente

Lo mismo que `motor/`, con sus constantes tal cual:

| Paso | Cómo |
| --- | --- |
| Remuestreo | 11.025 Hz — el contenido que sirve para acordes vive bajo 2 kHz |
| Ventana | 4096 muestras (372 ms), salto de 1024 (93 ms) |
| Cromagrama | banco de filtros triangulares de semitono, MIDI 24–96, plegado a 12 |
| Plantillas | 61: doce fundamentales × `maj min maj7 min7 7`, más el silencio |
| Pesos | fundamental 1,3 y quinta 1,1 — son las que sobreviven a la mezcla |
| Suavizado | Viterbi con permanencia 0,96 |

El Viterbi es lo que separa un cifrado legible de una lista de ruido: sin él la
salida parpadea en cada golpe de bombo.

## Lo que sí está medido

La página abre analizando una progresión que sintetiza ella misma, y como la
respuesta se conoce se puede comprobar en vez de creérsela:

```
se esperaban  C:maj A:min F:maj G:7 C:maj A:min D:min7 G:7
salieron      C:maj A:min F:maj G:7 C:maj A:min D:min7 G:7
              8 de 8 en su sitio
```

Distingue G7 de G y Dm7 de Dm, que es donde se juega lo de «acordes complejos».

## Lo que NO está medido

**Nada con una mezcla real.** Ni una canción con batería, bajo y voz. Ocho de
ocho sobre tonos sintetizados dice que la tubería está bien montada; no dice
qué tal reconoce música. Y no se puede saber mientras `corpus/` tenga cero
ficheros `.lab`.

Por eso la página exporta **`.lab` en formato Harte**: cada pista que se cifre
aquí y se corrija a mano es una entrada de corpus, y con corpus el motor se
puede medir de verdad — y comparar contra el camino neuronal.

## El APK

```bash
cd movil
npm install
npm run apk        # genera el proyecto Android y compila
```

El proyecto Android no está en el repositorio: lo genera `cap add android` en
cada compilación. `apk.yml` hace lo mismo en CI y deja el APK en la publicación
`acordes-latest`.

El APK existe por algo concreto: **dentro de un artifact el selector de ficheros
no llega a abrirse**, así que no hay forma de darle un MP3 de verdad. En un APK
sí. Lo primero que hay que comprobar al instalarlo es justo eso — que el botón
de elegir pista abre el selector del teléfono.
