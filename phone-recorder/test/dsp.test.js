// SYNTHETIC TEST: checks the live DSP demo (high-pass, moving RMS, threshold
// detection) with generated signals. Every number is made up for the test.
// Run: node test/dsp.test.js
const fs = require('fs'), path = require('path'), assert = require('assert');
const html = fs.readFileSync(path.join(__dirname, '..', 'index.html'), 'utf8');
const src = html.slice(html.indexOf('// ===== BEGIN CORE'), html.indexOf('// ===== END CORE'));
const m = { exports: {} };
new Function('module', src + '\nmodule.exports = Core;')(m);
const Core = m.exports;
let passed = 0;
const t = (name, fn) => { fn(); passed++; console.log('ok  ' + name); };
console.log('=== SYNTHETIC TEST DATA: generated signals, not measurements ===');

// Deterministic pseudo-random noise so the test is repeatable.
let seed = 1;
const rnd = () => ((seed = (seed * 16807) % 2147483647) / 2147483647 - 0.5);

// Synthetic stream at an uneven ~60 Hz: gravity on z, small noise, optional bumps.
// Bump shape: damped 5 Hz oscillation, 60 ms decay, lasting 0.3 s, long enough to be
// seen at ~60 Hz. opts.short uses a 20 ms decay at 12 Hz instead (an impact that is
// too fast for the phone's sample rate).
function stream(seconds, bumpsAt, opts = {}) {
  const out = []; let t = 0;
  while (t < seconds * 1e6) {
    let z = 9.81, x = 0.05 * rnd(), y = 0.05 * rnd();
    for (const b of bumpsAt) {
      const d = (t - b * 1e6) / 1e6;
      if (opts.short) { if (d >= 0 && d < 0.08) x += 8 * Math.exp(-d / 0.02) * Math.cos(2 * Math.PI * 12 * d); }
      else if (d >= 0 && d < 0.3) x += 8 * Math.exp(-d / 0.06) * Math.cos(2 * Math.PI * 5 * d);
    }
    if (opts.tilt) z = 9.81 * Math.cos(0.3 * Math.sin(2 * Math.PI * 0.1 * t / 1e6));
    out.push([Math.round(t), x, y, z]);
    t += 1e6 / 60 + (opts.jitter ? 4000 * rnd() : 0);
  }
  return out;
}
function run(samples, opts) {
  const p = Core.createProcessor(opts);
  const res = samples.map((s) => p.push(...s));
  return { res, bumps: p.finish(), settings: p.settings };
}

t('constant gravity is removed by the high-pass filter (envelope near 0)', () => {
  const { res } = run(stream(5, []));
  const tail = res.slice(-60).map((r) => r.env);
  assert.ok(Math.max(...tail) < 0.2, 'envelope too high: ' + Math.max(...tail));
});
t('quiet signal: no detections', () => {
  assert.strictEqual(run(stream(10, [], { jitter: true })).bumps.length, 0);
});
t('slow tilting (0.1 Hz) is not detected as a bump', () => {
  assert.strictEqual(run(stream(10, [], { tilt: true })).bumps.length, 0);
});
t('three separate bumps -> three detections near the right times', () => {
  const at = [2.0, 4.5, 7.0];
  const { bumps } = run(stream(9, at, { jitter: true }));
  assert.strictEqual(bumps.length, 3);
  bumps.forEach((b, i) => assert.ok(Math.abs(b.t_us / 1e6 - at[i]) < 0.1, `bump ${i} at ${b.t_us / 1e6}`));
  bumps.forEach((b) => assert.ok(b.peak_env >= 2.0));
});
t('bump during warm-up (first 1 s) is ignored', () => {
  assert.strictEqual(run(stream(3, [0.3])).bumps.length, 0);
});
t('two bumps closer than the refractory period count once', () => {
  assert.strictEqual(run(stream(5, [2.0, 2.15])).bumps.length, 1);
});
t('manual mode: higher threshold -> fewer detections', () => {
  const s = stream(9, [2.0, 4.5, 7.0]);
  assert.ok(run(s, { threshold_mode: 'manual', threshold_mps2: 50 }).bumps.length === 0);
  assert.strictEqual(run(s, { threshold_mode: 'manual', threshold_mps2: 2 }).bumps.length, 3);
});
t('repeated / backwards timestamps do not crash or produce NaN', () => {
  const p = Core.createProcessor();
  for (const s of [[0, 0, 0, 9.8], [16000, 0, 0, 9.8], [16000, 1, 0, 9.8], [10000, 0, 0, 9.8], [32000, 0, 0, 9.8]]) {
    const r = p.push(...s);
    assert.ok(Number.isFinite(r.env) && Number.isFinite(r.hp));
  }
});
t('undersampling: a 20 ms impact can fall between 60 Hz samples and be missed', () => {
  // Same bump times as above, short impacts, no jitter: at least one is missed.
  // Fixed 2 m/s2 threshold so only the sampling changes between runs.
  const manual = { threshold_mode: 'manual', threshold_mps2: 2 };
  const short = run(stream(9, [2.0, 4.5, 7.0], { short: true }), manual);
  const n = short.bumps.length;
  // the envelope peak seen at 60 Hz depends on where the samples land
  const peaks = short.res.map((r) => r.env);
  assert.ok(Math.max(...peaks) < 8, 'sampled peak should be far below the 8 m/s2 true peak');
  assert.ok(n < 3, 'expected a miss, got ' + n);
  console.log('    (SYNTHETIC) short impacts detected: ' + n + ' of 3; this is why VibraSmash samples at 20 kHz');
});
// ---- Auto threshold: max(median + 6 x MAD of background, minimum) ----
t('medianMad matches the pipeline definition (unscaled MAD)', () => {
  const mm = Core.medianMad([1, 2, 3, 4, 100]);       // devs 2,1,0,1,97 -> median 1
  assert.strictEqual(mm.median, 3);
  assert.strictEqual(mm.mad, 1);
  const even = Core.medianMad([1, 2, 3, 4]);           // median 2.5; devs 1.5,.5,.5,1.5 -> 1
  assert.strictEqual(even.median, 2.5);
  assert.strictEqual(even.mad, 1);
});
t('auto is the default mode', () => {
  assert.strictEqual(Core.DSP_DEFAULTS.threshold_mode, 'auto');
  assert.strictEqual(Core.DSP_DEFAULTS.mad_k, 6);
});
t('auto: no threshold (and no detection) until 1 s of background after warm-up', () => {
  const { res, bumps } = run(stream(3, [1.5]));
  const at = (sec) => res[Math.round(sec * 60)];
  assert.ok(Number.isNaN(at(0.5).thr) && Number.isNaN(at(1.5).thr));
  assert.strictEqual(at(1.5).thr_info.limited_by, 'no_background');
  assert.ok(Number.isFinite(at(2.5).thr));
  assert.strictEqual(bumps.length, 0);
});
t('auto: quiet background -> threshold held at the minimum', () => {
  const { res } = run(stream(6, []));
  const ti = res[res.length - 1].thr_info;
  assert.strictEqual(ti.limited_by, 'minimum');
  assert.strictEqual(ti.thr, Core.DSP_DEFAULTS.min_threshold_mps2);
  assert.ok(ti.median + 6 * ti.mad < ti.thr);
});
t('auto: threshold equals median + 6 x MAD of the background when above the minimum', () => {
  const { res } = run(stream(6, []), { min_threshold_mps2: 0.001 });
  const last = res[res.length - 1], ti = last.thr_info;
  assert.strictEqual(ti.limited_by, 'statistical');
  assert.ok(Math.abs(ti.thr - (ti.median + 6 * ti.mad)) < 1e-12);
  // recompute from the envelope values the processor saw (last 5 s, no bumps here)
  const t_end = res.length - 1;
  const bg = res.slice(0, t_end).map((r, i) => ({ i, env: r.env }))
    .filter(({ i }) => i / 60 >= 1.0 && (t_end - i) / 60 <= 5.0 + 1e-9).map((x) => x.env);
  const mm = Core.medianMad(bg);
  assert.ok(Math.abs(ti.median - mm.median) < 0.02 && Math.abs(ti.mad - mm.mad) < 0.02);
});
t('auto: three bumps on a quiet background -> three detections', () => {
  const at = [3.0, 5.5, 8.0];
  const { bumps } = run(stream(10, at, { jitter: true }));
  assert.strictEqual(bumps.length, 3);
  bumps.forEach((b, i) => assert.ok(Math.abs(b.t_us / 1e6 - at[i]) < 0.1));
});
t('auto: ongoing vibration raises the threshold, so the vibration itself is not counted', () => {
  // strong ongoing vibration (e.g. walking) plus one bump of similar size
  const s = stream(10, []).map(([tu, x, y, z]) => [tu, x + 1.2 * Math.sin(2 * Math.PI * 7 * tu / 1e6), y, z]);
  const quietMin = run(s, { min_threshold_mps2: 0.5 });
  const ti = quietMin.res[quietMin.res.length - 1].thr_info;
  assert.strictEqual(ti.limited_by, 'statistical');
  assert.ok(ti.thr > 0.5);
  // a fixed 0.5 m/s2 threshold would fire on the vibration itself
  assert.ok(run(s, { threshold_mode: 'manual', threshold_mps2: 0.5 }).bumps.length >= 1);
  assert.strictEqual(quietMin.bumps.length, 0);
});
t('auto: bump samples are left out of the background (threshold unchanged by a bump)', () => {
  const quiet = run(stream(9, []), { min_threshold_mps2: 0.001 });
  seed = 1;
  const withBump = run(stream(9, [6.0]), { min_threshold_mps2: 0.001 });
  seed = 1;
  assert.strictEqual(withBump.bumps.length, 1);
  const i = Math.round(6.8 * 60);   // after the bump has ended
  const a = quiet.res[i].thr, b = withBump.res[i].thr;
  assert.ok(Math.abs(a - b) / a < 0.5, 'threshold moved from ' + a + ' to ' + b);
});
t('auto: each bump records the threshold it crossed and why', () => {
  const { bumps } = run(stream(9, [3.0]));
  assert.strictEqual(bumps[0].limited_by, 'minimum');
  assert.strictEqual(bumps[0].thr, Core.DSP_DEFAULTS.min_threshold_mps2);
});
t('buildDemoMeta lists settings and bump times', () => {
  const { bumps, settings } = run(stream(9, [2.0, 4.5, 7.0]));
  const meta = Core.buildDemoMeta(settings, bumps);
  assert.ok(meta.includes('demo_n_bumps=3'));
  assert.ok(meta.includes('demo_threshold_mode=auto_median_plus_k_mad'));
  assert.ok(meta.includes('demo_mad_k=6'));
  assert.ok(meta.includes('demo_min_threshold_mps2=0.5'));
  assert.ok(/demo_bump_threshold_limited_by=minimum minimum minimum/.test(meta));
  const manual = Core.buildDemoMeta(Core.createProcessor({ threshold_mode: 'manual', threshold_mps2: 2 }).settings, []);
  assert.ok(manual.includes('demo_threshold_mode=manual') && manual.includes('demo_threshold_mps2=2'));
  assert.ok(!manual.includes('demo_mad_k'));
  assert.ok(/demo_bump_t_s=2\.\d{3} 4\.\d{3} 7\.\d{3}/.test(meta));
  assert.ok(meta.includes('not the VibraSmash pipeline settings'));
  console.log('--- SYNTHETIC demo meta ---\n' + meta + '--- end SYNTHETIC demo meta ---');
});
console.log(`\n${passed} tests passed (SYNTHETIC data only)`);
