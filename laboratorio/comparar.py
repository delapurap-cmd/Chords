#!/usr/bin/env python3
"""Corre varios reconocedores sobre el corpus y saca la tabla de WCSR.

Este script es el que contesta la pregunta más cara del proyecto: cuánto se
puede sacar como mucho en mezclas completas con tus canciones. Con esa tabla
delante se decide qué portar; sin ella se elige a ciegas.

Uso:
    python comparar.py ../corpus
    python comparar.py ../corpus --candidatos chordino,crema

Los candidatos que no estén instalados se saltan solos, así que se puede
empezar con uno y añadir el resto sin tocar nada.
"""

import argparse
import sys
from pathlib import Path

try:
    import mir_eval
    import numpy as np
except ImportError:
    sys.exit("Faltan dependencias. Instala con: pip install -r requirements.txt")

NIVELES = {
    "fundamental": "root",
    "mayor/menor": "majmin",
    "séptimas": "sevenths",
    "mayor/menor + inv": "majmin_inv",
    "séptimas + inv": "sevenths_inv",
}


# ═══════════════════════════════════════════════════════════════════════════
# CANDIDATOS
# ═══════════════════════════════════════════════════════════════════════════
# Cada uno recibe la ruta de un audio y devuelve [(inicio, fin, etiqueta), …].
# Si su librería no está instalada, devuelve None y se salta.

def candidato_crema(ruta):
    try:
        import crema
    except ImportError:
        return None
    modelo = crema.models.chord.ChordModel()
    salida = modelo.predict(filename=str(ruta))
    return [(float(o.time), float(o.time + o.duration), o.value)
            for o in salida.data]


def candidato_madmom(ruta):
    try:
        from madmom.features.chords import (
            CNNChordFeatureProcessor, CRFChordRecognitionProcessor,
        )
    except ImportError:
        return None
    caracteristicas = CNNChordFeatureProcessor()(str(ruta))
    acordes = CRFChordRecognitionProcessor()(caracteristicas)
    return [(float(a[0]), float(a[1]), str(a[2])) for a in acordes]


def candidato_madmom_deep(ruta):
    try:
        from madmom.features.chords import (
            DeepChromaProcessor, DeepChromaChordRecognitionProcessor,
        )
    except ImportError:
        return None
    croma = DeepChromaProcessor()(str(ruta))
    acordes = DeepChromaChordRecognitionProcessor()(croma)
    return [(float(a[0]), float(a[1]), str(a[2])) for a in acordes]


CANDIDATOS = {
    "crema": candidato_crema,
    "madmom": candidato_madmom,
    "madmom_deep": candidato_madmom_deep,
}

# El motor v0 en Dart y Chordino se puntúan desde .lab ya generados, con
# `motor/bin/comparar_lab.dart` o pasando su carpeta con --lab.


# ═══════════════════════════════════════════════════════════════════════════
# EVALUACIÓN
# ═══════════════════════════════════════════════════════════════════════════

def puntuar(ruta_ref, tramos_est):
    """WCSR a todos los niveles, más la duración para poder agregar."""
    intervalos_ref, etiquetas_ref = mir_eval.io.load_labeled_intervals(str(ruta_ref))
    if not tramos_est:
        return {n: 0.0 for n in NIVELES}, float(intervalos_ref.max() - intervalos_ref.min())

    intervalos_est = np.array([[t[0], t[1]] for t in tramos_est])
    etiquetas_est = [t[2] for t in tramos_est]

    intervalos_est, etiquetas_est = mir_eval.util.adjust_intervals(
        intervalos_est, etiquetas_est,
        intervalos_ref.min(), intervalos_ref.max(),
        mir_eval.chord.NO_CHORD, mir_eval.chord.NO_CHORD,
    )
    intervalos, ref, est = mir_eval.util.merge_labeled_intervals(
        intervalos_ref, etiquetas_ref, intervalos_est, etiquetas_est
    )
    duraciones = mir_eval.util.intervals_to_durations(intervalos)

    notas = {}
    for nombre, metrica in NIVELES.items():
        comparaciones = getattr(mir_eval.chord, metrica)(ref, est)
        notas[nombre] = mir_eval.chord.weighted_accuracy(comparaciones, duraciones)
    return notas, float(intervalos_ref.max() - intervalos_ref.min())


def main():
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("corpus", help="carpeta con parejas cancion.wav + cancion.lab")
    p.add_argument("--candidatos", default=",".join(CANDIDATOS),
                   help="cuáles probar, separados por comas")
    args = p.parse_args()

    corpus = Path(args.corpus)
    referencias = sorted(corpus.glob("*.lab"))
    if not referencias:
        sys.exit(f"No hay ningún .lab en {corpus}. El corpus son parejas .wav + .lab.")

    pedidos = [c.strip() for c in args.candidatos.split(",") if c.strip()]
    desconocidos = [c for c in pedidos if c not in CANDIDATOS]
    if desconocidos:
        sys.exit(f"Candidatos desconocidos: {', '.join(desconocidos)}")

    print(f"Corpus: {len(referencias)} canciones en {corpus}\n")
    resultados = {}

    for nombre in pedidos:
        funcion = CANDIDATOS[nombre]
        acumulado = {n: 0.0 for n in NIVELES}
        segundos = 0.0
        analizadas = 0
        disponible = True

        for ref in referencias:
            audio = ref.with_suffix(".wav")
            if not audio.exists():
                print(f"  {nombre}: falta {audio.name}, se salta")
                continue
            try:
                tramos = funcion(audio)
            except Exception as e:
                print(f"  {nombre}: falló con {audio.name} → {e}")
                continue
            if tramos is None:
                print(f"  {nombre}: no instalado, se salta")
                disponible = False
                break
            notas, duracion = puntuar(ref, tramos)
            for n in NIVELES:
                acumulado[n] += notas[n] * duracion
            segundos += duracion
            analizadas += 1

        if disponible and analizadas:
            resultados[nombre] = {n: acumulado[n] / segundos for n in NIVELES}
            print(f"  {nombre}: {analizadas} canciones")

    if not resultados:
        sys.exit("\nNingún candidato pudo correr. Instala alguno y repite.")

    ancho = max(len(n) for n in resultados) + 2
    print("\n" + "═" * (22 + ancho * len(resultados)))
    print(f"  {'nivel':<20}" + "".join(f"{n:>{ancho}}" for n in resultados))
    print("─" * (22 + ancho * len(resultados)))
    for nivel in NIVELES:
        fila = f"  {nivel:<20}"
        for n in resultados:
            fila += f"{resultados[n][nivel]:>{ancho}.1%}"
        print(fila)
    print("═" * (22 + ancho * len(resultados)))
    print("\nEl nivel de séptimas es el que importa para 'acordes complejos'.")
    print("Si ahí el mejor candidato se queda corto, el producto no puede")
    print("prometer precisión: tiene que prometer un borrador editable.")


if __name__ == "__main__":
    main()
