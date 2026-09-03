# Laboratorio

**Esto no se envía a nadie.** Corre en tu portátil, sin conexión, y sirve para
una sola cosa: averiguar qué modelo merece la pena portar antes de gastar
semanas portándolo.

La app final no habla con ningún servidor ni con ninguna API. Lo que acaba en
el móvil es el paquete `motor/` en Dart y, cuando llegue el v2, un archivo
`.tflite` dentro del propio APK.

## Para qué sirve cada cosa

| Script | Qué hace |
|---|---|
| `comparar.py` | Corre varios reconocedores sobre el corpus y saca la tabla de WCSR |
| `verificar_puntuador.py` | Comprueba que el puntuador en Dart coincide con `mir_eval` |

`verificar_puntuador.py` es el que menos glamour tiene y el más importante.
El motor se mide con el puntuador escrito en Dart, para que la misma cifra
salga en `dart test` y dentro de la app. Pero la autoridad del campo es
`mir_eval`. Si los dos no coinciden, la cifra con la que tomamos decisiones
está mal, y todo lo demás da igual.

## Instalación

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

`madmom` puede dar guerra al instalarse porque compila extensiones y arrastra
versiones antiguas de numpy. Si se atraganta, déjalo fuera al principio:
`comparar.py` se salta los candidatos que no estén instalados y sigue con el
resto.

## Antes de apoyarte en una librería, mira su licencia

Vas a cobrar por la app, así que esto no es un detalle:

- **Essentia** es AGPL. Enlazarla en una app cerrada es un problema serio.
- **madmom** es de código abierto, pero el uso comercial tiene condiciones
  propias. Léelas antes de construir nada encima.
- librosa, mir_eval, Demucs y basic-pitch tienen licencias permisivas.

Verifica los términos actuales tú mismo. Están escritos aquí como recordatorio
de mirar, no como resumen fiable.
