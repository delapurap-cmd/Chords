/* El motor clásico: cromagrama + plantillas + Viterbi.
   Portado de `chords/motor` (Dart) con sus mismas constantes, así que lo que
   suena aquí es lo mismo que suena allí.

   Vive en su propio fichero, y no dentro de la página, por una razón
   concreta: lo que no se puede cargar sin abrir un navegador entero tampoco
   se puede medir. `corpus/evaluar.mjs` lo carga tal cual, sin copiar ni una
   línea, y lo pasa por los 99 loops etiquetados de la app. Si el motor se
   toca, la medida se entera. */
const Clasico = (function () {
const A = {
  fs: 11025, ventana: 4096, salto: 1024, notaMin: 24, notaMax: 96,
  permanencia: 0.96, temperatura: 0.08, umbralSilencio: 0.015,
};
const RAICES = ['C','C#','D','D#','E','F','F#','G','G#','A','A#','B'];
const CALIDADES = ['maj','min','maj7','min7','7'];
const INTERVALOS = { maj:[0,4,7], min:[0,3,7], maj7:[0,4,7,11], min7:[0,3,7,10], '7':[0,4,7,10] };
const SUFIJO = { maj:'', min:'m', maj7:'maj7', min7:'m7', '7':'7' };

/** FFT radix-2 iterativa, in-place, sobre partes real e imaginaria. */
function fft(re, im) {
  const n = re.length;
  for (let i = 1, j = 0; i < n; i++) {
    let bit = n >> 1;
    for (; j & bit; bit >>= 1) j ^= bit;
    j ^= bit;
    if (i < j) { let t = re[i]; re[i] = re[j]; re[j] = t; t = im[i]; im[i] = im[j]; im[j] = t; }
  }
  for (let len = 2; len <= n; len <<= 1) {
    const ang = -2 * Math.PI / len, wr = Math.cos(ang), wi = Math.sin(ang);
    for (let i = 0; i < n; i += len) {
      let cr = 1, ci = 0;
      for (let k = 0; k < len / 2; k++) {
        const ur = re[i + k], ui = im[i + k];
        const vr = re[i + k + len / 2] * cr - im[i + k + len / 2] * ci;
        const vi = re[i + k + len / 2] * ci + im[i + k + len / 2] * cr;
        re[i + k] = ur + vr; im[i + k] = ui + vi;
        re[i + k + len / 2] = ur - vr; im[i + k + len / 2] = ui - vi;
        const nr = cr * wr - ci * wi; ci = cr * wi + ci * wr; cr = nr;
      }
    }
  }
}

/* Un filtro triangular por semitono, centrado en su frecuencia y ancho medio
   semitono a cada lado: la forma barata de pasar de bins lineales de FFT a
   escala logarítmica sin montar una CQT entera. */
function bancoDeSemitonos() {
  const bins = A.ventana / 2 + 1, hzPorBin = A.fs / A.ventana, banco = [];
  for (let nota = A.notaMin; nota <= A.notaMax; nota++) {
    const centro = 440 * Math.pow(2, (nota - 69) / 12);
    const abajo = centro * Math.pow(2, -0.5 / 12), arriba = centro * Math.pow(2, 0.5 / 12);
    const idx = [], pes = [];
    const k0 = Math.max(0, Math.min(bins - 1, Math.floor(abajo / hzPorBin)));
    const k1 = Math.max(0, Math.min(bins - 1, Math.ceil(arriba / hzPorBin)));
    for (let k = k0; k <= k1; k++) {
      const hz = k * hzPorBin;
      if (hz < abajo || hz > arriba) continue;
      const p = hz <= centro ? (hz - abajo) / (centro - abajo) : (arriba - hz) / (arriba - centro);
      if (p > 0) { idx.push(k); pes.push(p); }
    }
    // En el grave un semitono puede ser más estrecho que un bin y quedarse sin
    // ninguno: se coge el más cercano para no dejar el hueco.
    if (!idx.length) { idx.push(Math.max(0, Math.min(bins - 1, Math.round(centro / hzPorBin)))); pes.push(1); }
    banco.push({ idx: Int32Array.from(idx), pes: Float64Array.from(pes) });
  }
  return banco;
}

function vocabulario() {
  const v = [];
  for (let r = 0; r < 12; r++) for (const cal of CALIDADES) {
    const c = new Float64Array(12);
    for (const iv of INTERVALOS[cal]) c[(r + iv) % 12] = 1;
    // La fundamental y la quinta pesan más: son las que sobreviven a la mezcla.
    c[r] = 1.3;
    c[(r + 7) % 12] = Math.max(c[(r + 7) % 12], 1.1);
    normalizar(c);
    v.push({ harte: RAICES[r] + ':' + cal, mostrar: RAICES[r] + SUFIJO[cal], croma: c, silencio: false });
  }
  const plano = new Float64Array(12).fill(1);
  normalizar(plano);
  v.push({ harte: 'N', mostrar: '—', croma: plano, silencio: true });
  return v;
}
function normalizar(v) {
  let s = 0; for (const x of v) s += x * x;
  const n = Math.sqrt(s);
  if (n > 1e-12) for (let i = 0; i < v.length; i++) v[i] /= n;
}
function similitud(croma, plantilla) {
  let punto = 0, nc = 0;
  for (let i = 0; i < 12; i++) { punto += croma[i] * plantilla[i]; nc += croma[i] * croma[i]; }
  nc = Math.sqrt(nc);
  return nc < 1e-12 ? 0 : punto / nc;   // la plantilla ya viene normalizada
}
function aLogProbabilidades(p, temperatura) {
  const k = p.length, e = new Float64Array(k);
  let max = -Infinity;
  for (let i = 0; i < k; i++) { e[i] = p[i] / temperatura; if (e[i] > max) max = e[i]; }
  let suma = 0;
  for (let i = 0; i < k; i++) { e[i] = Math.exp(e[i] - max); suma += e[i]; }
  const log = new Float64Array(k);
  for (let i = 0; i < k; i++) log[i] = Math.log(Math.max(e[i] / suma, 1e-300));
  return log;
}

/* Viterbi con transición uniforme: en cada paso sólo importan el mejor
   anterior y el propio, así que no hace falta materializar la matriz K×K. */
function viterbi(emisiones, k, permanencia) {
  if (!emisiones.length) return [];
  const logQuedarse = Math.log(permanencia);
  const logCambiar = Math.log((1 - permanencia) / (k - 1));
  let ant = Float64Array.from(emisiones[0]);
  const rastro = [];
  for (let t = 1; t < emisiones.length; t++) {
    let mejor = ant[0], iMejor = 0;
    for (let j = 1; j < k; j++) if (ant[j] > mejor) { mejor = ant[j]; iMejor = j; }
    const cur = new Float64Array(k), paso = new Uint8Array(k);
    for (let j = 0; j < k; j++) {
      const quedarse = ant[j] + logQuedarse, cambiar = mejor + logCambiar;
      if (quedarse >= cambiar) { cur[j] = quedarse + emisiones[t][j]; paso[j] = j; }
      else { cur[j] = cambiar + emisiones[t][j]; paso[j] = iMejor; }
    }
    rastro.push(paso); ant = cur;
  }
  let mejor = ant[0], fin = 0;
  for (let j = 1; j < k; j++) if (ant[j] > mejor) { mejor = ant[j]; fin = j; }
  const camino = new Array(emisiones.length);
  camino[emisiones.length - 1] = fin;
  for (let t = rastro.length - 1; t >= 0; t--) { fin = rastro[t][fin]; camino[t] = fin; }
  return camino;
}

/** Analiza PCM mono a 11025 Hz. Cede el hilo cada tanto para que la página
    siga respondiendo: una canción son un par de miles de FFT. */
async function analizar(pcm, avisa) {
  const banco = bancoDeSemitonos(), voc = vocabulario();
  const ventana = new Float64Array(A.ventana);
  for (let i = 0; i < A.ventana; i++) ventana[i] = 0.5 - 0.5 * Math.cos(2 * Math.PI * i / (A.ventana - 1));
  const re = new Float64Array(A.ventana), im = new Float64Array(A.ventana);
  const nFrames = Math.max(0, Math.floor((pcm.length - A.ventana) / A.salto) + 1);
  const emisiones = [];
  const segsPorFrame = A.salto / A.fs;

  for (let f = 0; f < nFrames; f++) {
    const off = f * A.salto;
    let energia = 0;
    for (let i = 0; i < A.ventana; i++) {
      const s = pcm[off + i];
      re[i] = s * ventana[i]; im[i] = 0;
      energia += Math.abs(s);
    }
    energia /= A.ventana;
    fft(re, im);

    const croma = new Float64Array(12);
    for (let n = 0; n < banco.length; n++) {
      const { idx, pes } = banco[n];
      let suma = 0;
      for (let k = 0; k < idx.length; k++) {
        const b = idx[k];
        suma += Math.hypot(re[b], im[b]) * pes[k];
      }
      croma[(A.notaMin + n) % 12] += suma;
    }
    // Normalizar por el máximo deja cada frame comparable sin que los pasajes
    // fuertes pesen más que los suaves.
    let max = 0; for (const v of croma) if (v > max) max = v;
    if (max > 1e-12) for (let i = 0; i < 12; i++) croma[i] /= max;

    const silencioso = energia < A.umbralSilencio;
    const punt = new Float64Array(voc.length);
    for (let c = 0; c < voc.length; c++) {
      // El silencio no compite por parecido de croma sino por falta de
      // energía; si el frame suena, su puntuación se hunde.
      punt[c] = voc[c].silencio
        ? (silencioso ? 1 : 0)
        : similitud(croma, voc[c].croma) * (silencioso ? 0.3 : 1);
    }
    emisiones.push(aLogProbabilidades(punt, A.temperatura));

    if ((f & 63) === 0) { avisa(f / Math.max(1, nFrames)); await new Promise(r => setTimeout(r)); }
  }

  const camino = viterbi(emisiones, voc.length, A.permanencia);
  const tramos = [];
  for (let f = 0; f < camino.length; f++) {
    const v = voc[camino[f]];
    const ini = f * segsPorFrame, fin = (f + 1) * segsPorFrame;
    const ult = tramos[tramos.length - 1];
    // 1 ms de tolerancia: los bordes vienen de coma flotante.
    if (ult && ult.harte === v.harte && Math.abs(ini - ult.fin) < 1e-3) ult.fin = fin;
    else tramos.push({ ini, fin, harte: v.harte, mostrar: v.mostrar });
  }
  return tramos;
}

  return { analizar, A, RAICES, CALIDADES };
})();

if (typeof module !== 'undefined' && module.exports) module.exports = Clasico;
