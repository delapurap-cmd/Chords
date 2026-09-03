# Chords

Reconocimiento de acordes de pistas multi-instrumento, **100% sin conexión**.
Se le pasa una canción y devuelve el cifrado.

Sin servidores. Sin APIs de terceros. Lo que acabe en el móvil corre en el
móvil.

## Dónde está cada cosa

```
motor/        Paquete Dart puro. Sin una sola importación de Flutter.
              Es lo que se embarca en la app.
laboratorio/  Python. Corre en tu portátil, no se envía a nadie.
              Sirve para decidir qué modelo merece la pena portar.
corpus/       Canciones etiquetadas. El audio no se sube; los .lab sí.
```

Que el motor no dependa de Flutter es deliberado: así el mismo código corre
bajo `dart test` contra el corpus en segundos **y** se embarca tal cual en la
app, sin que lo que se mide y lo que se envía puedan separarse.

## Empezar

```bash
cd motor
dart pub get
dart test

# Sin canciones todavía: se genera un corpus sintético para ver la tubería.
dart run bin/generar_corpus_falso.dart /tmp/corpus_falso
dart run bin/evaluar.dart /tmp/corpus_falso
```

Con canciones de verdad:

```bash
dart run bin/evaluar.dart ../corpus
dart run bin/evaluar.dart ../corpus --permanencia 0.98 --guardar /tmp/salidas
```

Para preparar el corpus, mira `corpus/README.md`.

## Cómo va el motor

```
audio → cromagrama → plantillas de acorde → Viterbi → cifrado
```

El **cromagrama** dice cuánta energía hay en cada una de las doce notas a lo
largo del tiempo. Las **plantillas** comparan cada instante contra los 60
acordes del vocabulario. El **Viterbi** impone que cambiar de acorde cuesta,
así que solo cambia cuando la evidencia lo justifica; sin él la salida
parpadearía en cada golpe de bombo.

El vocabulario del v0 son cinco calidades (`maj`, `min`, `maj7`, `min7`, `7`)
por doce fundamentales, más el silencio.

## Qué es esto y qué no

**Esto es la línea base, no el producto.** No hay ningún modelo entrenado
todavía: son plantillas y DSP. Existe por dos razones:

1. Cierra la tubería completa, de audio a `.lab` puntuado.
2. Da un número contra el que competir. Si un modelo con IA no le gana a esto
   con holgura, el problema está en el modelo, no en la tarea.

**El orden importa.** Primero la regla, después el motor. Sin una cifra no se
puede saber si un cambio mejora o empeora, y en este problema la intuición
engaña: pruebas con tres canciones, suena bien, y resulta que solo has
ajustado los parámetros a esas tres.

## Cómo se mide

**WCSR** (*weighted chord symbol recall*): segundos acertados entre segundos
totales. Ponderado por duración, que es lo que se percibe al escuchar.

Se puntúa a cinco niveles a la vez, y eso es lo que distingue *«se equivoca de
fundamental»* de *«acierta la fundamental pero no la calidad»* — fallos con
causas y arreglos distintos:

| Nivel | Qué pregunta |
|---|---|
| fundamental | ¿acierta la nota raíz? |
| mayor/menor | ¿acierta además si es mayor o menor? |
| séptimas | ¿distingue maj7, min7 y séptima de dominante? |
| + inversión | ¿acierta también el bajo? |

**El nivel de séptimas es el que importa aquí**, porque es donde se juega lo
de reconocer acordes complejos.

Junto al WCSR sale la **cobertura**: qué parte del corpus entra en cada nivel.
Los acordes de la referencia que caen fuera del vocabulario de un nivel no se
cuentan ni a favor ni en contra — un `C:sus4` no es un fallo del motor a nivel
mayor/menor, es una pregunta que ese nivel no hace. Si la cobertura es baja,
esa nota se apoya en poco tiempo y hay que mirarla con recelo.

## El camino

- **v0 — hecho.** Cromagrama, plantillas y Viterbi. La línea base.
- **v1.** Cromagrama NNLS para quitar armónicos, cromagrama de graves aparte
  para las inversiones, y sincronización a los beats.
- **v2.** Modelo entrenado, exportado a TFLite y ejecutado en el móvil.

Para el v2, dos cosas que conviene tener presentes desde ya:

**Un puñado de canciones calibra, no entrena.** Diez o veinte sirven para
saber si vas bien y para ajustar parámetros. Entrenar una red pide cientos.
Los corpus públicos regalan las etiquetas pero no el audio, y ese es el cuello
de botella real.

**El banco de filtros va dentro del grafo.** Una STFT es una convolución con
núcleos fijos y un cromagrama es una multiplicación por una matriz fija. Si
las dos se meten en el modelo exportado, queda un solo archivo que va de audio
crudo a acordes. Si no, hay que reimplementar librosa en Dart.

## Lo que falta

- Decodificar mp3 y m4a en el móvil. Sin servidor hay que hacerlo en local, y
  en Flutter eso pide código nativo en las dos plataformas. Tarea aparte.
- Seguimiento de beats y compases, para dar un cifrado por compases en vez de
  una lista de segundos.
- Detección de tonalidad, para escribir fa sostenido o sol bemol según toque.
