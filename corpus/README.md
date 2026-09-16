# Corpus

Aquí van las canciones etiquetadas: audio real con la respuesta al lado. **El
audio no se sube al repositorio** (está en `.gitignore`): son archivos grandes
y con derechos. Los `.lab` sí, porque son texto, pesan nada y son lo que de
verdad vale.

Este directorio llevaba desde el principio vacío, y eso tenía una consecuencia
concreta: «qué motor reconoce mejor los acordes» era una opinión. La única
cifra que existía salía de una progresión que la propia página sintetizaba con
senoides, sin batería, sin bajo y sin voz.

## El corpus que ya estaba, sin saberlo

**More Than Modes trae 113 loops tocados con instrumentos reales, y cada uno
viene con su cifrado escrito** en `assets/backing_tracks_charts/*.json`. Eso es
exactamente un corpus etiquetado, y no hubo que etiquetar nada a mano.

```bash
python3 corpus/desde_mtm.py --repo ../more-than-modes   # construye lab/
node corpus/evaluar.mjs   --repo ../more-than-modes     # mide los dos motores
```

De las 113 quedan **99**: las otras 14 se descartan porque los compases que
declaran no cuadran con lo que dura el audio, y una etiqueta puesta en el
momento equivocado no es neutra —haría quedar mal a un motor que acertó—. Por
lo mismo el tiempo sale de la duración dividida entre compases y no del `bpm`
declarado, que miente en varios álbumes: bossa y reggae van un 10 % cortos,
funk un 10 % largo, metal un 40 %. En realidad casi todos los loops están a
~2,405 s por compás.

## Lo que salió al medir

99 pistas, medido con CSR —la proporción de *tiempo* en el acorde correcto, que
es la medida estándar del campo—:

| | acorde exacto | raíz | tríada | velocidad |
|---|---|---|---|---|
| clásico (cromagrama) | **26,7 %** | 58,5 % | 41,2 % | 0,01× tiempo real |
| red neuronal (basic-pitch) | **26,4 %** | 61,9 % | 46,8 % | 1,23× tiempo real |

La red gana en 39 pistas, pierde en 41 y empata en 19.

### Tres cosas que esto cambia

**1. La red no es mejor. Es distinta.** Empatan dentro del ruido, y la red
tarda cien veces más. La expectativa razonable antes de medir era que una red
entrenada con música real ganara cómodamente en música real; no pasa. Lo que el
dato no dice es que la red sea inútil: dice que el trabajo pendiente no está en
cambiar de motor.

**2. Fallan en sitios opuestos, y eso sí es aprovechable.**

| | metal | rock | reggae | soul | jazz |
|---|---|---|---|---|---|
| clásico | 3,8 % | 4,1 % | **44,1 %** | **51,3 %** | **26,7 %** |
| red | **25,8 %** | **55,0 %** | 5,7 % | 36,7 % | 20,1 % |

El clásico se hunde justo donde la guitarra distorsionada llena el espectro de
armónicos —metal y rock, donde baja del 5 %— y ahí la red saca diez veces más.
En reggae pasa lo contrario. Un motor que elija según la pista, o que combine
los dos, tiene mucho margen antes de necesitar un modelo mejor.

**3. El cuello de botella es la calidad del acorde, no la fundamental.** Las
dos aciertan la raíz el **59-62 %** del tiempo y el acorde entero sólo el
**26 %**. O sea: saben *en qué* acorde están y se equivocan al decir *cuál*. Y
cada motor se equivoca en una dirección fija:

```
clásico   F:maj → F:maj7    E:min → E:maj7    A#:maj → A#:maj7   (pone séptimas de más)
red       B:min7 → B:min    D:min7 → D:min    E:min7 → E:min     (se le caen las séptimas)
```

En metal el clásico saca 76,2 % de raíz y 3,8 % de acorde: oye bien la quinta
pelada y luego le cuelga una séptima que no está.

## Lo que se probó y NO funcionó

Que el clásico ponga séptimas de más parecía un artefacto conocido de comparar
por coseno: una plantilla de cuatro notas recoge ruido que a la tríada se le
escapa, así que gana sin merecerlo. Se le puso un descuento por nota extra y se
barrió:

```
descuento  0,00 → CSR 26,7 %    0,06 → 26,1 %    0,15 → 14,6 %
           0,04 → CSR 26,7 %    0,10 → 23,4 %
```

**No ayuda: empeora.** La hipótesis era falsa y el arreglo se retiró en vez de
dejarlo puesto con un número bonito. Queda escrito para que nadie lo vuelva a
intentar creyendo que es obvio.

## Cómo está montada la medida

`evaluar.mjs` levanta un servidor, abre Chromium y carga **los mismos
`web/ia.js` y `web/clasico.js` que sirve la página**, decodificando el MP3 con
el mismo `OfflineAudioContext`. No hay una copia del motor para pruebas: si se
toca el motor, la medida se entera al siguiente pase. Por eso el motor clásico
salió del `<script>` de `reconocedor.html` a su propio fichero — lo que no se
puede cargar sin abrir la interfaz entera tampoco se puede medir.

Opciones útiles: `--motor ia|clasico|ambos`, `--album metal`, `--paso 4` (una de
cada cuatro pistas, que reparte los siete álbumes) y `--ajuste
pesoRaiz=1,pesoQuinta=1`, que toca las constantes del motor sin editar ficheros.

## Los límites de este corpus, dichos claro

- **Son loops de 10 a 20 segundos**, no canciones. Falta estructura, cambios de
  sección y una voz delante.
- **El cifrado es el que se escribió para tocar encima**, no una transcripción
  de lo que suena. Si la chuleta dice `Cm7` y el bajo no toca la séptima, la
  referencia pide una séptima que en el audio no está. Parte del hueco entre
  26 % y 62 % es esto y no error del motor; cuánta parte, no se sabe.
- **Los acordes duran un compás entero.** Nada mide qué tal van los cambios
  rápidos.
- `sus4` y `dim` aparecen 5 veces en todo el corpus, y el motor clásico ni
  siquiera puede nombrarlos: su vocabulario son cinco calidades.

Por eso sigue haciendo falta etiquetar canciones de verdad, y para eso está
todo lo que viene a continuación.

---

# Añadir canciones a mano

## Cómo se prepara una canción

Una pareja de archivos con el mismo nombre:

```
corpus/
  cancion.wav      ← audio
  cancion.lab      ← etiquetas
```

**El audio en WAV.** El MVP en Dart no decodifica mp3 a propósito: hacerlo en
Dart es un pozo y el corpus se convierte una sola vez. Mono o estéreo da igual,
el motor lo pasa a mono. Cualquier frecuencia vale. (`evaluar.mjs`, que corre
en el navegador, sí acepta mp3 — lo decodifica el propio Chromium.)

**Las etiquetas en `.lab`**, una línea por acorde:

```
0.000	2.612	G:maj
2.612	5.100	E:min7
5.100	7.400	N
```

Tres columnas: inicio en segundos, fin en segundos, acorde. Separadas por
tabulador o por espacios, las dos valen. Las líneas que empiezan por `#` son
comentarios.

## La forma más rápida de hacerlo: Audacity

1. Abre la canción.
2. Ve marcando regiones donde suena cada acorde (`Ctrl+B` crea una etiqueta).
3. Escribe el acorde en cada una.
4. **Archivo → Exportar → Exportar etiquetas.**

Lo que sale es prácticamente un `.lab` ya. Es el mismo trabajo que cortar la
canción en trozos, pero conservando los tiempos, que es lo que permite medir el
producto de verdad.

La página del reconocedor también exporta `.lab`: cifrar ahí una canción,
corregir a mano lo que esté mal y guardar es bastante más rápido que empezar de
cero.

## La notación

Es la de Harte, la que usan todos los corpus del campo:

| Escribes | Significa |
|---|---|
| `C` o `C:maj` | do mayor |
| `A:min` | la menor |
| `G:7` | sol séptima de dominante |
| `F:maj7` | fa mayor séptima |
| `D:min7` | re menor séptima |
| `C#:maj` o `Db:maj` | lo mismo, da igual cómo lo escribas |
| `G:7/3` | sol séptima con la tercera en el bajo |
| `C:maj(9)` | do mayor con novena añadida |
| `A:min7(*5)` | la menor séptima sin la quinta |
| `N` | no suena ningún acorde |
| `X` | no se sabe (no se puntúa) |

`N` importa más de lo que parece: marca las intros, los solos de batería y los
finales. Si etiquetas eso como si hubiera acorde, el motor aprende a inventar
acordes donde no los hay.

## Dos avisos sobre cómo elegir los trozos

**No te quedes solo con lo limpio.** Es tentador etiquetar los pasajes donde el
acorde se oye claro y saltarse los sucios. Si haces eso, el corpus miente a tu
favor: sale una nota alta que no predice nada. Mete los cambios rápidos, los
puentes y los sitios donde entra la voz. Son los que van a definir la
experiencia real.

**`X` cuando dudes, no un acorde a boleo.** Una etiqueta inventada es peor que
ninguna, porque penaliza al motor por acertar. `X` se descarta al puntuar.

## Comprobar que el corpus está bien

```bash
cd ../motor
dart run bin/evaluar.dart ../corpus
```

Si un `.lab` tiene una línea rota o una etiqueta que no se entiende, lo dice
con el nombre del archivo y el número de línea.
