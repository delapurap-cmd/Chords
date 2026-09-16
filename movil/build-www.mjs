/* Prepara `www/` a partir de la página de `web/`.
 *
 * Es una copia y poco más, a propósito: el reconocedor es un solo fichero sin
 * dependencias externas —ni librería, ni pesos, ni fuentes de Google—, así que
 * no hay nada que empaquetar ni que quitar. Eso mismo es lo que permite que el
 * APK funcione en avión, que es la premisa del repositorio.
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

console.log('www/ preparada desde web/reconocedor.html');
