/* Prepara `www/` a partir de `web/`.
 *
 * Es una copia, a propósito: no hay empaquetador ni paso de compilación. Lo
 * que se copia es todo lo que la página necesita, incluida la red neuronal
 * —el modelo y TensorFlow.js—, porque nada se descarga en tiempo de ejecución.
 * Eso es lo que permite que el APK funcione en avión, que es la premisa del
 * repositorio.
 */
import { cp, rm, mkdir } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const aqui = dirname(fileURLToPath(import.meta.url));
const raiz = resolve(aqui, '..');
const salida = resolve(aqui, 'www');

await rm(salida, { recursive: true, force: true });
await mkdir(salida, { recursive: true });
await cp(resolve(raiz, 'web/reconocedor.html'), resolve(salida, 'index.html'));
// La IA viaja dentro: el modelo (904 KB) y TensorFlow.js (1,5 MB). Eso es lo
// que permite que haya red neuronal Y que el APK funcione en avión.
for (const item of ['web/ia.js', 'web/vendor', 'web/modelo']) {
  await cp(resolve(raiz, item), resolve(salida, item.replace('web/', '')), { recursive: true });
}

console.log('www/ preparada desde web/reconocedor.html');
