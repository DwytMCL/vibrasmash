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
t('higher threshold -> fewer detections', () => {
  const s = stream(9, [2.0, 4.5, 7.0]);
  assert.ok(run(s, { threshold_mps2: 50 }).bumps.length === 0);
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
  const n = run(stream(9, [2.0, 4.5, 7.0], { short: true })).bumps.length;
  assert.ok(n < 3, 'expected a miss, got ' + n);
  console.log('    (SYNTHETIC) short impacts detected: ' + n + ' of 3; this is why VibraSmash samples at 20 kHz');
});
t('buildDemoMeta lists settings and bump times', () => {
  const { bumps, settings } = run(stream(9, [2.0, 4.5, 7.0]));
  const meta = Core.buildDemoMeta(settings, bumps);
  assert.ok(meta.includes('demo_n_bumps=3'));
  assert.ok(/demo_bump_t_s=2\.\d{3} 4\.\d{3} 7\.\d{3}/.test(meta));
  assert.ok(meta.includes('not the VibraSmash pipeline settings'));
  console.log('--- SYNTHETIC demo meta ---\n' + meta + '--- end SYNTHETIC demo meta ---');
});
console.log(`\n${passed} tests passed (SYNTHETIC data only)`);
