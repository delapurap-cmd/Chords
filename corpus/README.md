# Corpus

Aquí van las canciones etiquetadas. **El audio no se sube al repositorio**
(está en `.gitignore`): son archivos grandes y con derechos. Los `.lab` sí,
porque son texto, pesan nada y son lo que de verdad vale.

## Cómo se prepara una canción

Una pareja de archivos con el mismo nombre:

```
corpus/
  cancion.wav      ← audio
  cancion.lab      ← etiquetas
```

**El audio en WAV.** El MVP no decodifica mp3 a propósito: hacerlo en Dart es
un pozo y el corpus se convierte una sola vez. Mono o estéreo da igual, el
motor lo pasa a mono. Cualquier frecuencia vale.

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
canción en trozos, pero conservando los tiempos, que es lo que permite medir
el producto de verdad.

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

**No te quedes solo con lo limpio.** Es tentador etiquetar los pasajes donde
el acorde se oye claro y saltarse los sucios. Si haces eso, el corpus miente a
tu favor: sale una nota alta que no predice nada. Mete los cambios rápidos,
los puentes y los sitios donde entra la voz. Son los que van a definir la
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
