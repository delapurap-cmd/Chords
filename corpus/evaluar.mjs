#!/usr/bin/env node
/**
 * Mide los dos motores contra el corpus de `lab/`.
 *
 * Hasta ahora la única cifra que existía —«7 de 8»— salía de un ejemplo
 * sintetizado por la propia página: ondas limpias, sin batería, sin bajo, sin
 * voz, sin reverb. Eso no dice nada sobre música de verdad. Esto sí: 99 loops
 * grabados con instrumentos reales, cada uno con su cifrado escrito por quien
 * los hizo.
 *
 *   node evaluar.mjs --repo /ruta/a/more-than-modes [--motor ia|clasico|ambos]
 *                    [--limite N] [--album metal]
 *
 * ## Qué se mide
 *
 * **CSR** (chord symbol recall), que es la medida estándar: se recorre el
 * tiempo en rejilla de 10 ms y se cuenta qué proporción cae en un acorde
 * acertado. Es por tiempo y no por acorde a propósito —acertar un acorde que
 * dura cuatro compases vale más que acertar uno de paso, igual que al oído.
 *
 * Y dos cifras más para saber *cómo* falla, que es lo que dice qué arreglar:
 *
 * - **raíz**: mismo fundamental, calidad aparte. Si la raíz está bien y la
 *   calidad mal, el problema es el vocabulario de plantillas. Si la raíz está
 *   mal, el problema es el cromagrama.
 * - **tríada**: raíz y mayor/menor, ignorando séptimas. Un `C:maj` por un
 *   `C:maj7` es un error de anotación tanto como de oído: en un loop de jazz
 *   la séptima la toca el bajo o nadie.
 */

import { createServer } from 'node:http';
import { readFile, readdir } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import path from 'node:path';
import { chromium } from 'playwright';

const AQUI = path.dirname(new URL(import.meta.url).pathname);
const RAIZ = path.resolve(AQUI, '..');
const REJILLA = 0.01;   // 10 ms

const arg = (n, d) => {
  const i = process.argv.indexOf('--' + n);
  return i > 0 ? process.argv[i + 1] : d;
};

/* ── El corpus ───────────────────────────────────────────────────────────── */

function leerLab(txt) {
  return txt.trim().split('\n').filter(Boolean).map((l) => {
    const [ini, fin, ...resto] = l.trim().split(/\s+/);
    return { ini: +ini, fin: +fin, harte: resto.join(' ') };
  });
}

const enT = (tramos, t) => {
  for (const x of tramos) if (t >= x.ini && t < x.fin) return x.harte;
  return null;
};

const raizDe = (h) => (h === 'N' || !h ? h : h.split(':')[0]);
const TRIADA = { maj: 'M', maj7: 'M', 7: 'M', aug: 'M', sus4: 'M', sus2: 'M',
                 min: 'm', min7: 'm', dim: 'm', hdim7: 'm' };
const triadaDe = (h) => (h === 'N' || !h ? h : raizDe(h) + ':' + (TRIADA[h.split(':')[1]] || '?'));

/** Compara referencia y predicción en rejilla de 10 ms. */
function puntuar(ref, pred, dur) {
  let n = 0, exacto = 0, raiz = 0, triada = 0;
  const fallos = new Map();
  for (let t = 0; t < dur; t += REJILLA) {
    const r = enT(ref, t);
    if (r === null) continue;      // fuera de la parte etiquetada
    const p = enT(pred, t);
    n++;
    if (p === r) exacto++;
    else {
      const k = `${r} → ${p || '—'}`;
      fallos.set(k, (fallos.get(k) || 0) + 1);
    }
    if (raizDe(p) === raizDe(r)) raiz++;
    if (triadaDe(p) === triadaDe(r)) triada++;
  }
  return { n, exacto, raiz, triada, fallos };
}

/* ── Un servidor para que el navegador vea los ficheros ──────────────────── */

const TIPOS = { '.html': 'text/html', '.js': 'text/javascript', '.json': 'application/json',
                '.bin': 'application/octet-stream', '.mp3': 'audio/mpeg' };

function servidor(repo) {
  const srv = createServer(async (req, res) => {
    const url = decodeURIComponent(req.url.split('?')[0]);
    let f = null;
    if (url.startsWith('/web/')) f = path.join(RAIZ, url.slice(1));
    else if (url.startsWith('/audio/')) {
      const nombre = url.slice('/audio/'.length);
      for (const d of await readdir(path.join(repo, 'assets/sounds/albums'))) {
        const c = path.join(repo, 'assets/sounds/albums', d, nombre);
        if (existsSync(c)) { f = c; break; }
      }
    } else if (url === '/' || url === '/banco.html') f = path.join(AQUI, 'banco.html');
    if (!f || !existsSync(f)) { res.writeHead(404); return res.end('no'); }
    res.writeHead(200, { 'content-type': TIPOS[path.extname(f)] || 'application/octet-stream' });
    res.end(await readFile(f));
  });
  return new Promise((ok) => srv.listen(0, () => ok({ srv, puerto: srv.address().port })));
}

/* ── El pase ─────────────────────────────────────────────────────────────── */

const pct = (a, b) => (b ? (100 * a / b).toFixed(1) : '0.0').padStart(5) + ' %';

async function main() {
  const repo = arg('repo', '/home/user/more-than-modes');
  const quiere = arg('motor', 'ambos');
  const motores = quiere === 'ambos' ? ['clasico', 'ia'] : [quiere];
  const limite = +arg('limite', 0);
  const album = arg('album', null);
  // Una de cada N pistas: para barrer ajustes hace falta una muestra que
  // toque los siete álbumes, no las primeras N, que serían todas bossanova.
  const paso = +arg('paso', 1);
  // `--ajuste pesoRaiz=1,pesoQuinta=1` toca las constantes del motor sin
  // editar el fichero, que es lo que permite barrer sin ensuciar el repo.
  const ajuste = arg('ajuste', null);

  const indice = JSON.parse(await readFile(path.join(AQUI, 'indice.json'), 'utf8'));
  let pistas = indice.pistas;
  if (album) pistas = pistas.filter((p) => p.album === album);
  if (paso > 1) pistas = pistas.filter((_, i) => i % paso === 0);
  if (limite) pistas = pistas.slice(0, limite);

  const { srv, puerto } = await servidor(repo);
  // El contenedor trae un Chromium ya instalado que no coincide con la
  // compilación que espera el paquete de npm; se apunta al que hay.
  const yaHay = '/opt/pw-browsers/chromium';
  const nav = await chromium.launch(existsSync(yaHay) ? { executablePath: yaHay } : {});
  const pag = await nav.newPage();
  pag.on('console', (m) => { if (m.type() === 'error') console.error('  [navegador]', m.text()); });
  await pag.goto(`http://localhost:${puerto}/banco.html`);
  await pag.evaluate(() => window.preparar());
  if (ajuste) {
    await pag.evaluate((txt) => {
      for (const par of txt.split(',')) {
        const [k, v] = par.split('=');
        IA.AJ[k.trim()] = +v;   // `const IA` no cuelga de window
      }
    }, ajuste);
    console.log(`  ajuste: ${ajuste}`);
  }

  const todo = {};
  for (const motor of motores) {
    const acc = { n: 0, exacto: 0, raiz: 0, triada: 0, ms: 0, seg: 0 };
    const porAlbum = {}, fallos = new Map(), porPista = [];
    console.log(`\n${'═'.repeat(64)}\n  ${motor === 'ia' ? 'RED NEURONAL (basic-pitch)' : 'MOTOR CLÁSICO (cromagrama)'}  ·  ${pistas.length} pistas\n${'═'.repeat(64)}`);

    for (let i = 0; i < pistas.length; i++) {
      const p = pistas[i];
      const ref = leerLab(await readFile(path.join(AQUI, 'lab', p.lab), 'utf8'));
      let r;
      try {
        r = await pag.evaluate(([u, m]) => window.correr(u, m),
          [`/audio/${encodeURIComponent(p.audio)}`, motor]);
      } catch (e) {
        console.log(`  ${p.audio.padEnd(20)} ERROR ${String(e).slice(0, 60)}`);
        continue;
      }
      const s = puntuar(ref, r.tramos, Math.min(r.dur, ref[ref.length - 1].fin));
      acc.n += s.n; acc.exacto += s.exacto; acc.raiz += s.raiz; acc.triada += s.triada;
      acc.ms += r.ms; acc.seg += r.dur;
      const a = porAlbum[p.album] || (porAlbum[p.album] = { n: 0, exacto: 0, raiz: 0 });
      a.n += s.n; a.exacto += s.exacto; a.raiz += s.raiz;
      for (const [k, v] of s.fallos) fallos.set(k, (fallos.get(k) || 0) + v);
      porPista.push({ audio: p.audio, album: p.album, csr: s.exacto / s.n });
      process.stdout.write(`\r  ${String(i + 1).padStart(3)}/${pistas.length}  ${p.audio.padEnd(22)} CSR ${pct(s.exacto, s.n)}   `);
    }
    console.log('\n');
    console.log(`  CSR (acorde exacto)   ${pct(acc.exacto, acc.n)}`);
    console.log(`  raíz correcta         ${pct(acc.raiz, acc.n)}`);
    console.log(`  tríada correcta       ${pct(acc.triada, acc.n)}`);
    console.log(`  velocidad             ${(acc.ms / 1000 / acc.seg).toFixed(2)}× el tiempo real`);
    console.log('\n  por álbum:');
    for (const [k, v] of Object.entries(porAlbum).sort((x, y) => y[1].exacto / y[1].n - x[1].exacto / x[1].n))
      console.log(`    ${k.padEnd(12)} CSR ${pct(v.exacto, v.n)}   raíz ${pct(v.raiz, v.n)}`);
    console.log('\n  confusiones más caras (por tiempo):');
    for (const [k, v] of [...fallos].sort((a, b) => b[1] - a[1]).slice(0, 10))
      console.log(`    ${String((100 * v / acc.n).toFixed(1)).padStart(5)} %  ${k}`);
    todo[motor] = { acc, porPista };
  }

  if (motores.length === 2) {
    const [c, a] = [todo.clasico, todo.ia];
    console.log(`\n${'═'.repeat(64)}\n  CARA A CARA\n${'═'.repeat(64)}`);
    console.log(`  clásico   CSR ${pct(c.acc.exacto, c.acc.n)}   raíz ${pct(c.acc.raiz, c.acc.n)}`);
    console.log(`  neuronal  CSR ${pct(a.acc.exacto, a.acc.n)}   raíz ${pct(a.acc.raiz, a.acc.n)}`);
    let gana = 0, pierde = 0;
    for (let i = 0; i < c.porPista.length; i++) {
      if (a.porPista[i].csr > c.porPista[i].csr + 0.02) gana++;
      else if (c.porPista[i].csr > a.porPista[i].csr + 0.02) pierde++;
    }
    console.log(`  la red gana en ${gana} pistas, pierde en ${pierde}, empata en ${c.porPista.length - gana - pierde}`);
  }

  await nav.close();
  srv.close();
}

main().catch((e) => { console.error(e); process.exit(1); });
