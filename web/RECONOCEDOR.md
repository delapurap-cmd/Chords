# Reconocedor de acordes — página y APK

Se le da un MP3 o un WAV y devuelve el cifrado. Trae **dos motores** y se
cambia de uno a otro en un desplegable. Ya hay datos para decidir, y lo que
dicen es que **el desplegable se queda**: medidos contra 99 loops con
instrumentos reales empatan en el total (26,7 % y 26,4 % de acierto) pero
fallan en sitios opuestos —el clásico se hunde en metal y rock, la red en
reggae—. Las cifras y cómo se sacaron están en [`corpus/README.md`](../corpus/README.md).

## Los dos motores

**Red neuronal.** Basic Pitch de Spotify (Apache-2.0) dice qué notas suenan; es
una red entrenada con música real, y ahí le gana de calle a una FFT: separa la
nota del armónico y aguanta la batería y la voz encima. Qué *acorde* forman esas
notas no lo decide la red —no está entrenada para eso— sino plantillas, una
estimación de tonalidad por perfiles de Krumhansl-Schmuckler y un Viterbi.

**Clásico.** El motor de `motor/` portado a JavaScript: cromagrama por banco de
filtros de semitono, plantillas y Viterbi. Instantáneo.

## IA sin conexión

El prototipo de `index.html` también usa Basic Pitch, pero descarga la librería
de `esm.sh` y los pesos de `jsdelivr` en cada arranque, y eso invierte la
premisa del README raíz: **«100% sin conexión. Sin APIs de terceros.»**

Aquí no hace falta elegir. El modelo son **904 KB** y TensorFlow.js **1,5 MB**:
los dos viajan dentro, y el grafo se llama directamente con
`tf.loadGraphModel` en vez de pasar por la librería. La firma del modelo se leyó
del propio `model.json`:

```
entrada   input_2      [lote, 43844, 1]   audio a 22.050 Hz, ventanas de ~2 s
salidas   Identity_1   [lote, 172, 88]    notas
          Identity_2   [lote, 172, 88]    ataques
```

**Ni una petición a la red**, con red neuronal incluida. Comprobado bloqueando
todo el tráfico externo en el navegador.

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

## Medido contra música real

99 loops de More Than Modes tocados con batería, bajo, guitarra y teclas, cada
uno con su cifrado escrito. CSR es la proporción de *tiempo* en el acorde
correcto:

| | acorde exacto | raíz | velocidad |
|---|---|---|---|
| clásico | 26,7 % | 58,5 % | 0,01× tiempo real |
| red neuronal | 26,4 % | 61,9 % | 1,23× tiempo real |

Tres cosas que salen de ahí, y que no se sabían antes:

- **La red no gana.** Empata, y tarda cien veces más. La expectativa era otra.
- **Se reparten los estilos**: metal 3,8 % el clásico contra 25,8 % la red;
  rock 4,1 % contra 55,0 %; reggae 44,1 % contra 5,7 %. Por eso hay dos motores
  y no uno.
- **Lo que falla es la calidad, no la fundamental.** Las dos aciertan la raíz
  seis veces de cada diez y el acorde entero sólo dos y media. El clásico pone
  séptimas de más (`F:maj` → `F:maj7`), la red se las come (`B:min7` →
  `B:min`). Ahí está el margen, y no en cambiar de modelo.

`corpus/README.md` tiene el desglose por álbum, las confusiones más caras y un
arreglo que se probó y **empeoró** las cifras, escrito para que nadie lo repita.

## Lo que se mide al abrir, y lo que ese número NO significa

La página abre analizando una progresión que sintetiza ella misma. Como la
respuesta se conoce, se puede comprobar en vez de creérsela:

```
se esperaban   C:maj A:min F:maj G:7 C:maj A:min D:min7 G:7

clásico        C:maj A:min F:maj G:7 C:maj A:min D:min7 G:7   8 de 8
red neuronal   C:maj A:min F:maj G:7 C:maj A:min F:maj  G:7   7 de 8
```

**El clásico gana, y eso no dice lo que parece.** El ejemplo son senoides con
tres armónicos: exactamente el material para el que un cromagrama de FFT es
perfecto, y exactamente el que una red entrenada con instrumentos reales nunca
ha visto. El resultado dice que las dos tuberías están bien montadas. No dice
cuál reconoce mejor una canción.

(La red confunde el Dm7 con un Fa. Comparten fa, la y do: tres de cuatro notas.
Es un error con sentido musical, no un disparate.)

Se puntúa **por tiempo**, mirando qué dice el motor en mitad de cada acorde. La
primera versión comparaba las listas posición a posición, y con eso un solo
tramo de más —la red oye un si disminuido en la caída del sol séptima, que es
literalmente lo que queda cuando se apaga la fundamental— desplazaba todo lo
siguiente y daba 4 de 8 con siete acordes bien.

## Lo que sigue sin estar medido

Los 99 loops son loops: diez o veinte segundos, un acorde por compás, sin
estructura y sin una voz delante. **Nada mide todavía una canción entera.** Y
el cifrado de referencia es el que se escribió para tocar encima, no una
transcripción de lo que suena: si la chuleta dice `Cm7` y el bajo no toca la
séptima, la referencia pide algo que en el audio no está. Parte del hueco entre
26 % y 62 % es eso y no fallo del motor; cuánta parte, no se sabe.

Por eso la página exporta **`.lab` en formato Harte**: cada canción que se
cifre aquí y se corrija a mano entra en el corpus, y `corpus/evaluar.mjs` la
recoge sin tocar nada.

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

## Velocidad

Con la red, en la máquina donde se desarrolló —sin GPU, con TensorFlow.js
cayendo en WebGL por software— el análisis va a **unas dos veces el tiempo real**.
En un teléfono con GPU debería ser bastante mejor, pero eso está por medir.

El tamaño del lote de ventanas se probó por si ayudaba y **no ayuda aquí**:

```
lote 1 → 12,3 s      lote 4 → 14,0 s
lote 2 → 12,3 s      lote 8 → 17,7 s
```

Sin GPU, agrupar no paraleliza y sólo agranda la reserva de memoria. Se deja en
2, que empata con 1 en el peor caso y deja margen donde sí haya GPU. Quien
vuelva a tocarlo, que lo mida en el aparato donde va a correr.
