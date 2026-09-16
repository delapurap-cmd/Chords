#!/usr/bin/env python3
"""Construye corpus etiquetado a partir de los backing tracks de More Than Modes.

El proyecto llevaba desde el principio con `corpus/` vacío: cero ficheros
`.lab`, o sea que ni el motor Dart ni ningún modelo se han medido nunca contra
música de verdad. Sin eso, elegir entre un reconocedor y otro es cuestión de fe.

Y resulta que el corpus ya existía sin saberlo. La app trae 113 loops con
instrumentos reales —batería, bajo, guitarra, teclas— repartidos en siete
estilos, y **cada uno viene con su cifrado escrito** en
`assets/backing_tracks_charts/*.json`. Eso es exactamente un corpus etiquetado:
audio real con la respuesta al lado.

    python3 desde_mtm.py --repo /ruta/al/repo/more-than-modes

Deja un `.lab` por pista en `lab/`, en notación Harte, y un `indice.json` con
lo que hace falta para evaluar.

## Lo que NO cuadra, y por qué se filtra

Los metadatos no son de fiar del todo, y conviene saberlo antes de usarlos:

- **El `bpm` declarado miente en varios álbumes.** Medido contra la duración
  real: rock y soul cuadran, bossa y reggae van un 10 % cortos, funk un 10 %
  largo y metal un 40 %. En realidad casi todos los loops están a ~2,405 s por
  compás —100 bpm en 4/4— sea cual sea el número que declaran.
- **El número de compases también falla en 14 de 113.** Un jazz declara seis
  compases y el audio tiene cuatro; cinco reggaes declaran cuatro y tienen
  cinco.

Así que el tiempo NO se saca del `bpm`, sino de la duración del audio dividida
entre los compases; y se descarta la pista cuando esos compases no cuadran con
lo que dura. Una etiqueta mal colocada en el tiempo es peor que no tenerla:
haría quedar mal a un reconocedor que acertó.
"""

import argparse
import glob
import json
import os
import re
import subprocess

AQUI = os.path.dirname(os.path.abspath(__file__))

# Casi todos los loops van a este compás, sea cual sea el bpm que declaran.
SEG_POR_COMPAS = 2.405

RAICES = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B']
BEMOLES = {'Db': 'C#', 'Eb': 'D#', 'Gb': 'F#', 'Ab': 'G#', 'Bb': 'A#',
           'Cb': 'B', 'Fb': 'E'}

# Al vocabulario del reconocedor. Las extensiones (9, 11, 13) no cambian la
# familia del acorde: un Cm7(9) se evalúa como Cm7, que es lo que cualquier
# medida de acordes hace con las tensiones.
CALIDAD = [
    (r'^maj7|^Maj7|^M7', 'maj7'),
    (r'^m7b5|^ø', 'hdim7'),
    (r'^dim7?|^dis7?|^°', 'dim'),
    (r'^m(?:aj)?9$|^m11|^m13|^m7|^m9|^m6|^m$|^min', 'min'),
    (r'^sus4|^sus$', 'sus4'),
    (r'^sus2', 'sus2'),
    (r'^aug|^\+', 'aug'),
    # El «6» solo no es dominante: un C6 es do-mi-sol-la, una mayor con sexta.
    # Cae más abajo, al caso mayor.
    (r'^7|^9$|^11$|^13$', '7'),
]


def normalizar(cifrado):
    """«Cm7(9)» → «C:min7». Devuelve None si no se entiende."""
    s = cifrado.strip().replace('(', '').replace(')', '')
    if s.upper() in ('N.C.', 'NC', 'N'):
        return 'N'  # silencio armónico, en Harte se escribe «N»
    m = re.match(r'^([A-G][b#]?)(.*)$', s)
    if not m:
        return None
    raiz, resto = m.group(1), m.group(2)
    raiz = BEMOLES.get(raiz, raiz)
    if raiz not in RAICES:
        return None

    # «Eb6/9» y «Eb9/#11/13» apilan tensiones con barras; «C/G» en cambio
    # nombra el bajo. Ni las tensiones ni la inversión cambian la familia del
    # acorde, así que en los dos casos vale con quedarse con lo primero.
    resto = resto.split('/')[0]
    # «No5», «add9», «add11»: quitan o añaden una nota sin mover la familia.
    resto = re.sub(r'No\d+|add\d+|omit\d+', '', resto, flags=re.I)

    # La séptima menor y la tríada menor comparten prefijo: se mira si hay 7.
    if re.match(r'^m(?!aj)', resto) and re.search(r'7|9|11|13', resto):
        return f'{raiz}:min7'
    for patron, cal in CALIDAD:
        if re.match(patron, resto):
            return f'{raiz}:{cal}'
    if resto == '' or resto in ('5', '6'):
        return f'{raiz}:maj'
    return None


def duracion(ruta):
    return float(subprocess.run(
        ['ffprobe', '-v', 'error', '-show_entries', 'format=duration',
         '-of', 'csv=p=0', ruta], capture_output=True, text=True).stdout)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--repo', required=True, help='repositorio de more-than-modes')
    ap.add_argument('--salida', default=os.path.join(AQUI, 'lab'))
    args = ap.parse_args()

    os.makedirs(args.salida, exist_ok=True)
    indice, descartes = [], []

    for fichero in sorted(glob.glob(os.path.join(args.repo, 'assets/backing_tracks_charts/*.json'))):
        for c in json.load(open(fichero))['charts']:
            audio = glob.glob(os.path.join(args.repo, 'assets/sounds/albums/*', c['file']))
            if not audio:
                descartes.append((c['file'], 'sin audio'))
                continue
            dur = duracion(audio[0])
            compases = round(dur / SEG_POR_COMPAS)
            if compases != c['bars']:
                descartes.append((c['file'], f"declara {c['bars']} compases y el audio da {compases}"))
                continue

            # El tiempo sale de la duración, no del bpm declarado.
            porCompas = dur / compases
            tramos, malo = [], None
            for i, barra in enumerate(c['progression'][:compases]):
                partes = barra.split()
                if not partes:
                    continue
                ancho = porCompas / len(partes)
                for k, cif in enumerate(partes):
                    harte = normalizar(cif)
                    if harte is None:
                        malo = cif
                        break
                    ini = i * porCompas + k * ancho
                    tramos.append((ini, ini + ancho, harte))
                if malo:
                    break
            if malo:
                descartes.append((c['file'], f'no entiendo el cifrado «{malo}»'))
                continue
            if not tramos:
                descartes.append((c['file'], 'sin cifrado'))
                continue

            # Se juntan los contiguos iguales, como en un .lab de verdad.
            juntos = []
            for ini, fin, h in tramos:
                if juntos and juntos[-1][2] == h:
                    juntos[-1][1] = fin
                else:
                    juntos.append([ini, fin, h])

            nombre = re.sub(r'[^a-z0-9]+', '-', c['file'].lower().replace('.mp3', '')).strip('-')
            with open(os.path.join(args.salida, nombre + '.lab'), 'w') as f:
                for ini, fin, h in juntos:
                    f.write(f'{ini:.3f} {fin:.3f} {h}\n')
            indice.append({'lab': nombre + '.lab', 'audio': c['file'],
                           'album': c['album'], 'duracion': round(dur, 3),
                           'compases': compases, 'acordes': len(juntos)})

    with open(os.path.join(AQUI, 'indice.json'), 'w') as f:
        json.dump({'segPorCompas': SEG_POR_COMPAS, 'pistas': indice}, f, indent=1, ensure_ascii=False)

    print(f'{len(indice)} pistas etiquetadas en {args.salida}')
    por_album = {}
    for x in indice:
        por_album[x['album']] = por_album.get(x['album'], 0) + 1
    for a, n in sorted(por_album.items()):
        print(f'  {a:<12} {n}')
    print(f'\n{len(descartes)} descartadas:')
    for f, motivo in descartes:
        print(f'  {f:<22} {motivo}')


if __name__ == '__main__':
    main()
