/* Reconocedor de acordes con red neuronal, sin conexión.
 *
 * Dos mitades que se reparten el trabajo por lo que cada una sabe hacer:
 *
 *   IA        Basic Pitch (Spotify, Apache-2.0) dice QUÉ NOTAS suenan. Es una
 *             red entrenada con música real, y ahí le gana de calle a un
 *             cromagrama de FFT: separa la nota del armónico, y aguanta la
 *             batería y la voz encima.
 *   Armonía   qué ACORDE forman esas notas no lo decide la red —no está
 *             entrenada para eso— sino plantillas, una estimación de tonalidad
 *             y un Viterbi. Eso es teoría musical, y escribirla es más fiable
 *             que esperar que un modelo de notas la deduzca.
 *
 * El prototipo de `index.html` hacía la primera mitad y se dejaba la segunda a
 * medias: votación de cinco cuadros en lugar de Viterbi, sin bajo, sin
 * tonalidad. El motor Dart hacía la segunda mitad bien y la primera con FFT.
 * Esto junta las dos buenas.
 *
 * No pide NADA a la red: el modelo (904 KB) y TensorFlow.js viajan dentro.
 */
const IA = (function () {
  'use strict';

  /* ── Constantes del modelo ──────────────────────────────────────────────
     Salen de la firma del propio `model.json`, no de adivinar:
       entrada  input_2     [lote, 43844, 1]
       salidas  Identity_1  [lote, 172, 88]   notas
                Identity_2  [lote, 172, 88]   ataques
     43844 = 22050·2 − 256, o sea dos segundos menos un salto. 172 cuadros por
     ventana dan un salto de 256 muestras: 86,13 cuadros por segundo. */
  const FS = 22050;
  const SALTO = 256;
  const MUESTRAS = FS * 2 - SALTO;          // 43844
  const CUADROS = 172;
  const SOLAPE = 30 * SALTO;                // 7680 muestras que comparten dos ventanas
  const RECORTE = 15;                       // cuadros que se tiran de cada borde
  const FPS = FS / SALTO;                   // 86,13
  const MIDI_BASE = 21;                     // la salida empieza en la0

  const RAICES = ['C','C#','D','D#','E','F','F#','G','G#','A','A#','B'];

  /* ── Vocabulario ────────────────────────────────────────────────────────
     Más ancho que el del motor v0 (cinco calidades) porque con notas de una
     red se puede: la evidencia es mucho más limpia y las calidades raras dejan
     de ser ruido. Pero no el vocabulario completo: cada clase que se añade
     compite con las demás, y sin corpus no hay forma de saber si ayuda. */
  const CALIDADES = [
    ['maj',  [0,4,7],     ''    ],
    ['min',  [0,3,7],     'm'   ],
    ['7',    [0,4,7,10],  '7'   ],
    ['maj7', [0,4,7,11],  'maj7'],
    ['min7', [0,3,7,10],  'm7'  ],
    ['dim',  [0,3,6],     'dim' ],
    ['hdim7',[0,3,6,10],  'm7b5'],
    ['sus4', [0,5,7],     'sus4'],
    ['aug',  [0,4,8],     'aug' ],
  ];

  function plantillas() {
    const v = [];
    for (let r = 0; r < 12; r++) for (const [cal, ivs, suf] of CALIDADES) {
      const c = new Float32Array(12);
      for (const iv of ivs) c[(r + iv) % 12] = 1;
      // La fundamental y la quinta pesan más: son las que sobreviven a la
      // mezcla, y con una red también son las que la voz menos enturbia.
      c[r] = 1.3;
      const q = (r + 7) % 12;
      if (ivs.indexOf(7) >= 0) c[q] = Math.max(c[q], 1.1);
      norma(c);
      v.push({ harte: RAICES[r] + ':' + cal, mostrar: RAICES[r] + suf,
               croma: c, raiz: r, ivs });
    }
    const plano = new Float32Array(12).fill(1);
    norma(plano);
    v.push({ harte: 'N', mostrar: '—', croma: plano, raiz: -1, ivs: [] });
    return v;
  }
  function norma(v) {
    let s = 0; for (const x of v) s += x * x;
    const n = Math.sqrt(s);
    if (n > 1e-12) for (let i = 0; i < v.length; i++) v[i] /= n;
  }

  /* ── Tonalidad ──────────────────────────────────────────────────────────
     Perfiles de Krumhansl-Schmuckler, que son de 1982 y siguen siendo la
     forma barata de acertar la tonalidad. Sirve para inclinar la balanza, no
     para decidir: un acorde prestado tiene que poder ganar si la evidencia
     está ahí. */
  const KS_MAYOR = [6.35,2.23,3.48,2.33,4.38,4.09,2.52,5.19,2.39,3.66,2.29,2.88];
  const KS_MENOR = [6.33,2.68,3.52,5.38,2.60,3.53,2.54,4.75,3.98,2.69,3.34,3.17];

  function tonalidad(cromaGlobal) {
    let mejor = { pc: 0, menor: false, r: -2 };
    for (let pc = 0; pc < 12; pc++) for (const menor of [false, true]) {
      const perfil = menor ? KS_MENOR : KS_MAYOR;
      let sx = 0, sy = 0, sxy = 0, sx2 = 0, sy2 = 0;
      for (let i = 0; i < 12; i++) {
        const x = cromaGlobal[(pc + i) % 12], y = perfil[i];
        sx += x; sy += y; sxy += x * y; sx2 += x * x; sy2 += y * y;
      }
      const num = 12 * sxy - sx * sy;
      const den = Math.sqrt((12 * sx2 - sx * sx) * (12 * sy2 - sy * sy));
      const r = den > 1e-9 ? num / den : 0;
      if (r > mejor.r) mejor = { pc, menor, r };
    }
    return mejor;
  }

  /** Grados que caben en la tonalidad: se premian un poco, no se imponen. */
  function premioTonal(voc, tono) {
    const escala = tono.menor ? [0,2,3,5,7,8,10] : [0,2,4,5,7,9,11];
    const dentro = new Set(escala.map((s) => (tono.pc + s) % 12));
    return voc.map((p) => {
      if (p.raiz < 0) return 0;
      const notas = p.ivs.map((iv) => (p.raiz + iv) % 12);
      const fuera = notas.filter((n) => !dentro.has(n)).length;
      // Media décima por nota ajena: se nota en los empates y no en lo demás.
      return -0.05 * fuera;
    });
  }

  /* ── El modelo ──────────────────────────────────────────────────────────── */
  let modelo = null;
  async function cargar(ruta) {
    if (!modelo) modelo = await tf.loadGraphModel(ruta);
    return modelo;
  }

  /** Notas por cuadro: [T][88] con la activación de cada nota. */
  async function notas(pcm, avisa) {
    const m = await cargar('modelo/model.json');
    // Se rellena el principio para que el primer cuadro caiga donde debe.
    const relleno = SOLAPE / 2;
    const largo = pcm.length + relleno;
    const paso = MUESTRAS - SOLAPE;
    const nVentanas = Math.max(1, Math.ceil((largo - SOLAPE) / paso));
    const fuera = [];

    /* Cuántas ventanas se le dan al modelo de una vez.

       Lo puse en 8 dando por hecho que agrupar sería más rápido —el coste fijo
       de cada llamada repartido entre más trabajo— y al medirlo era MÁS LENTO.
       Sobre 6 s de audio, en esta máquina:

           lote 1 → 12,3 s      lote 4 → 14,0 s
           lote 2 → 12,3 s      lote 8 → 17,7 s

       El motivo es que aquí no hay GPU y TensorFlow.js cae en WebGL por
       software, donde agrupar no paraleliza nada y sólo agranda la reserva de
       memoria. En un teléfono con GPU de verdad lo normal es lo contrario, así
       que se deja en 2: empata con 1 en el peor caso y deja margen para que
       ayude donde sí hay con qué. Si alguien vuelve a tocarlo, que lo mida en
       el aparato donde va a correr, no aquí. */
    const LOTE = 2;
    for (let w0 = 0; w0 < nVentanas; w0 += LOTE) {
      const n = Math.min(LOTE, nVentanas - w0);
      const trozo = new Float32Array(n * MUESTRAS);
      for (let b = 0; b < n; b++) {
        const ini = (w0 + b) * paso - relleno;
        for (let i = 0; i < MUESTRAS; i++) {
          const j = ini + i;
          trozo[b * MUESTRAS + i] = j >= 0 && j < pcm.length ? pcm[j] : 0;
        }
      }
      // `tidy` libera los tensores intermedios: sin esto una canción larga se
      // come la memoria del teléfono antes de la mitad.
      const salida = tf.tidy(() => {
        const x = tf.tensor(trozo, [n, MUESTRAS, 1]);
        const y = m.execute({ input_2: x }, ['Identity_1']);
        return (Array.isArray(y) ? y[0] : y).arraySync();
      });
      for (let b = 0; b < n; b++) {
        const w = w0 + b;
        // Los bordes de cada ventana los ve mal el modelo: se tiran, que para
        // eso las ventanas se solapan.
        const desde = w === 0 ? 0 : RECORTE;
        const hasta = w === nVentanas - 1 ? CUADROS : CUADROS - RECORTE;
        for (let f = desde; f < hasta; f++) fuera.push(salida[b][f]);
      }
      if (avisa) avisa(Math.min(1, (w0 + n) / nVentanas));
      await new Promise((r) => setTimeout(r));
    }
    return fuera;
  }

  /* ── De notas a acordes ──────────────────────────────────────────────── */

  /** Croma y croma de bajo, agregando cuadros de la red en bloques. */
  function cromas(act, bloque) {
    const T = act.length, out = [], bajos = [];
    for (let i = 0; i < T; i += bloque) {
      const c = new Float32Array(12), b = new Float32Array(12);
      for (let f = i; f < Math.min(T, i + bloque); f++) {
        const fila = act[f];
        for (let p = 0; p < 88; p++) {
          const v = fila[p];
          if (v < 0.15) continue;           // por debajo es ruido de la red
          const midi = MIDI_BASE + p;
          // Al cuadrado: una nota clara pesa mucho más que tres dudosas.
          c[midi % 12] += v * v;
          // Hasta do3 se considera registro de bajo, como en `motor/`.
          if (midi < 48) b[midi % 12] += v * v;
        }
      }
      let mx = 0; for (const x of c) if (x > mx) mx = x;
      if (mx > 1e-9) for (let k = 0; k < 12; k++) c[k] /= mx;
      let mb = 0; for (const x of b) if (x > mb) mb = x;
      if (mb > 1e-9) for (let k = 0; k < 12; k++) b[k] /= mb;
      out.push(c); bajos.push(b);
    }
    return { croma: out, bajo: bajos };
  }

  function coseno(a, b) {
    let p = 0, na = 0;
    for (let i = 0; i < 12; i++) { p += a[i] * b[i]; na += a[i] * a[i]; }
    na = Math.sqrt(na);
    return na < 1e-12 ? 0 : p / na;        // la plantilla ya viene normalizada
  }

  /* Viterbi con transición uniforme: en cada paso sólo importan el mejor
     anterior y el propio, así que no hace falta la matriz K×K. */
  function viterbi(logEm, k, permanencia) {
    if (!logEm.length) return [];
    const quedarse = Math.log(permanencia), cambiar = Math.log((1 - permanencia) / (k - 1));
    let ant = Float64Array.from(logEm[0]);
    const rastro = [];
    for (let t = 1; t < logEm.length; t++) {
      let mejor = ant[0], iM = 0;
      for (let j = 1; j < k; j++) if (ant[j] > mejor) { mejor = ant[j]; iM = j; }
      const cur = new Float64Array(k), paso = new Uint8Array(k);
      for (let j = 0; j < k; j++) {
        const q = ant[j] + quedarse, c = mejor + cambiar;
        if (q >= c) { cur[j] = q + logEm[t][j]; paso[j] = j; }
        else { cur[j] = c + logEm[t][j]; paso[j] = iM; }
      }
      rastro.push(paso); ant = cur;
    }
    let mejor = ant[0], fin = 0;
    for (let j = 1; j < k; j++) if (ant[j] > mejor) { mejor = ant[j]; fin = j; }
    const camino = new Array(logEm.length);
    camino[logEm.length - 1] = fin;
    for (let t = rastro.length - 1; t >= 0; t--) { fin = rastro[t][fin]; camino[t] = fin; }
    return camino;
  }

  function logProb(p, temperatura) {
    const k = p.length, e = new Float64Array(k);
    let mx = -Infinity;
    for (let i = 0; i < k; i++) { e[i] = p[i] / temperatura; if (e[i] > mx) mx = e[i]; }
    let s = 0;
    for (let i = 0; i < k; i++) { e[i] = Math.exp(e[i] - mx); s += e[i]; }
    const l = new Float64Array(k);
    for (let i = 0; i < k; i++) l[i] = Math.log(Math.max(e[i] / s, 1e-300));
    return l;
  }

  const AJ = {
    bloque: 8,            // cuadros por paso: 8/86,13 ≈ 93 ms, como en `motor/`
    temperatura: 0.08,
    permanencia: 0.96,
    umbralSilencio: 0.04, // por debajo de esto, la red no ve nada tocando
    pesoBajo: 0.25,       // cuánto ayuda el bajo a elegir la fundamental
    minimo: 0.4,          // segundos: por debajo, el tramo se absorbe
  };

  /** Todo junto: audio a 22050 Hz mono → tramos con acorde. */
  async function reconocer(pcm, avisa) {
    const act = await notas(pcm, (p) => avisa && avisa(p * 0.8, 'La red está oyendo las notas'));
    if (!act.length) return { tramos: [], tono: null };

    const { croma, bajo } = cromas(act, AJ.bloque);
    const voc = plantillas();
    const segsPorPaso = AJ.bloque / FPS;

    // Tonalidad global: la suma de todo lo que ha sonado.
    const global = new Float32Array(12);
    for (const c of croma) for (let i = 0; i < 12; i++) global[i] += c[i];
    const tono = tonalidad(global);
    const premio = premioTonal(voc, tono);

    const emisiones = [];
    for (let i = 0; i < croma.length; i++) {
      let energia = 0; for (const x of croma[i]) energia += x;
      const callado = energia < AJ.umbralSilencio * 12;
      const punt = new Float64Array(voc.length);
      for (let c = 0; c < voc.length; c++) {
        const p = voc[c];
        if (p.raiz < 0) { punt[c] = callado ? 1 : 0; continue; }
        // Parecido de croma, más un empujón si el bajo confirma la
        // fundamental, más el premio de la tonalidad.
        let s = coseno(croma[i], p.croma) + AJ.pesoBajo * bajo[i][p.raiz] + premio[c];
        if (callado) s *= 0.3;
        punt[c] = s;
      }
      emisiones.push(logProb(punt, AJ.temperatura));
    }

    const camino = viterbi(emisiones, voc.length, AJ.permanencia);
    let tramos = [];
    for (let i = 0; i < camino.length; i++) {
      const v = voc[camino[i]];
      const ini = i * segsPorPaso, fin = (i + 1) * segsPorPaso;
      const u = tramos[tramos.length - 1];
      if (u && u.harte === v.harte) u.fin = fin;
      else tramos.push({ ini, fin, harte: v.harte, mostrar: v.mostrar });
    }

    // Un acorde de un cuarto de segundo no es un acorde: es un tropiezo. Se
    // absorbe en el vecino más largo.
    for (let i = 0; i < tramos.length; i++) {
      if (tramos[i].fin - tramos[i].ini >= AJ.minimo || tramos.length < 3) continue;
      const izq = tramos[i - 1], der = tramos[i + 1];
      const destino = !izq ? der : !der ? izq
        : (izq.fin - izq.ini >= der.fin - der.ini ? izq : der);
      if (!destino) continue;
      destino.ini = Math.min(destino.ini, tramos[i].ini);
      destino.fin = Math.max(destino.fin, tramos[i].fin);
      tramos.splice(i, 1); i = Math.max(-1, i - 2);
    }
    // Y si al absorber quedaron dos iguales pegados, se juntan.
    const limpio = [];
    for (const t of tramos) {
      const u = limpio[limpio.length - 1];
      if (u && u.harte === t.harte) u.fin = t.fin; else limpio.push(t);
    }

    if (avisa) avisa(1, 'Listo');
    return { tramos: limpio, tono, cuadros: act.length, fps: FPS };
  }

  return { reconocer, cargar, RAICES, tonalidad };
})();
