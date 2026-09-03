#!/usr/bin/env python3
"""Comprueba que el puntuador en Dart da lo mismo que mir_eval.

El motor se mide con el puntuador escrito en Dart, para que la misma cifra
salga en `dart test` y dentro de la app sin que puedan separarse. Pero la
autoridad del campo es mir_eval. Si los dos no coinciden, la cifra con la que
tomamos decisiones está mal y todo lo demás da igual.

Uso:
    python verificar_puntuador.py <carpeta-referencias> <carpeta-estimaciones>

Las dos carpetas llevan .lab con el mismo nombre. Para generar las
estimaciones:

    cd ../motor
    dart run bin/evaluar.dart ../corpus --guardar /tmp/estimaciones
"""

import subprocess
import sys
from pathlib import Path

try:
    import mir_eval
except ImportError:
    sys.exit("Falta mir_eval. Instálalo con: pip install -r requirements.txt")

# Cómo se llama cada nivel a un lado y al otro.
NIVELES = {
    "fundamental": "root",
    "mayor/menor": "majmin",
    "séptimas": "sevenths",
    "mayor/menor + inv": "majmin_inv",
    "séptimas + inv": "sevenths_inv",
}

# Cuánto se admite de diferencia. No es cero porque las dos implementaciones
# cruzan los bordes con aritmética distinta, y a nivel de milisegundo eso se
# nota. Más de un punto porcentual sí es una discrepancia real.
TOLERANCIA = 0.01


def wcsr_de_mir_eval(ruta_ref: Path, ruta_est: Path, metrica: str) -> float:
    intervalos_ref, etiquetas_ref = mir_eval.io.load_labeled_intervals(str(ruta_ref))
    intervalos_est, etiquetas_est = mir_eval.io.load_labeled_intervals(str(ruta_est))

    intervalos_est, etiquetas_est = mir_eval.util.adjust_intervals(
        intervalos_est, etiquetas_est,
        intervalos_ref.min(), intervalos_ref.max(),
        mir_eval.chord.NO_CHORD, mir_eval.chord.NO_CHORD,
    )
    intervalos, ref, est = mir_eval.util.merge_labeled_intervals(
        intervalos_ref, etiquetas_ref, intervalos_est, etiquetas_est
    )
    duraciones = mir_eval.util.intervals_to_durations(intervalos)
    comparaciones = getattr(mir_eval.chord, metrica)(ref, est)
    return mir_eval.chord.weighted_accuracy(comparaciones, duraciones)


def wcsr_de_dart(carpeta_ref: Path, carpeta_est: Path) -> dict:
    """Corre el comparador de Dart y le saca los números."""
    salida = subprocess.run(
        ["dart", "run", "bin/comparar_lab.dart", str(carpeta_ref), str(carpeta_est)],
        cwd=Path(__file__).parent.parent / "motor",
        capture_output=True, text=True,
    )
    if salida.returncode != 0:
        sys.exit(f"El comparador de Dart falló:\n{salida.stderr}")

    valores = {}
    for linea in salida.stdout.splitlines():
        if "=" not in linea:
            continue
        nombre, cifra = linea.split("=", 1)
        try:
            valores[nombre.strip()] = float(cifra.strip())
        except ValueError:
            pass
    return valores


def main() -> None:
    if len(sys.argv) != 3:
        sys.exit(__doc__)

    carpeta_ref = Path(sys.argv[1])
    carpeta_est = Path(sys.argv[2])

    referencias = sorted(carpeta_ref.glob("*.lab"))
    if not referencias:
        sys.exit(f"No hay ningún .lab en {carpeta_ref}")

    print(f"Comparando {len(referencias)} canciones\n")

    # ── mir_eval, agregando por duración como hace el motor ─────────────────
    de_mir_eval = {}
    for nombre, metrica in NIVELES.items():
        acertado = 0.0
        total = 0.0
        for ref in referencias:
            est = carpeta_est / ref.name
            if not est.exists():
                continue
            intervalos, _ = mir_eval.io.load_labeled_intervals(str(ref))
            duracion = float(intervalos.max() - intervalos.min())
            wcsr = wcsr_de_mir_eval(ref, est, metrica)
            acertado += wcsr * duracion
            total += duracion
        de_mir_eval[nombre] = acertado / total if total else 0.0

    de_dart = wcsr_de_dart(carpeta_ref, carpeta_est)

    print(f"  {'nivel':<22}{'Dart':>10}{'mir_eval':>12}{'dif':>10}")
    print("  " + "-" * 52)
    hay_discrepancia = False
    for nombre in NIVELES:
        d = de_dart.get(nombre)
        m = de_mir_eval[nombre]
        if d is None:
            print(f"  {nombre:<22}{'—':>10}{m:>11.1%}{'?':>10}")
            continue
        dif = abs(d - m)
        marca = "  " if dif <= TOLERANCIA else " ←"
        if dif > TOLERANCIA:
            hay_discrepancia = True
        print(f"  {nombre:<22}{d:>9.1%}{m:>12.1%}{dif:>9.1%}{marca}")

    print()
    if hay_discrepancia:
        print("Hay niveles que no cuadran. El puntuador de Dart y mir_eval no")
        print("miden lo mismo, así que las cifras del motor no son de fiar")
        print("hasta arreglarlo.")
        sys.exit(1)
    print("Los dos puntuadores coinciden.")


if __name__ == "__main__":
    main()
