// SYNTHETIC TEST: checks the CSV/meta logic in index.html with fake events.
// Every number here is made up for the test. None of it is a measurement.
// Run: node test/core.test.js
const fs = require('fs'), path = require('path'), assert = require('assert');
const html = fs.readFileSync(path.join(__dirname, '..', 'index.html'), 'utf8');
const src = html.slice(html.indexOf('// ===== BEGIN CORE'), html.indexOf('// ===== END CORE'));
const m = { exports: {} };
new Function('module', src + '\nmodule.exports = Core;')(m);
const Core = m.exports;
let passed = 0;
const t = (name, fn) => { fn(); passed++; console.log('ok  ' + name); };

console.log('=== SYNTHETIC TEST DATA: fake events, not measurements ===');

t('pickAccel prefers includingGravity', () => {
  const r = Core.pickAccel({ accelerationIncludingGravity: { x: 1, y: 2, z: 9.8 }, acceleration: { x: 0, y: 0, z: 0 } });
  assert.deepStrictEqual(r, { x: 1, y: 2, z: 9.8, source: 'includingGravity' });
});
t('pickAccel falls back to acceleration when includingGravity is null', () => {
  assert.strictEqual(Core.pickAccel({ accelerationIncludingGravity: null, acceleration: { x: 0.1, y: 0.2, z: 0.3 } }).source, 'acceleration');
  assert.strictEqual(Core.pickAccel({ accelerationIncludingGravity: { x: null, y: null, z: null }, acceleration: { x: 0.1, y: 0.2, z: 0.3 } }).source, 'acceleration');
});
t('pickAccel returns null when there is no data (no invented sample)', () => {
  assert.strictEqual(Core.pickAccel({ accelerationIncludingGravity: null, acceleration: null }), null);
  assert.strictEqual(Core.pickAccel({ accelerationIncludingGravity: { x: null, y: 1, z: 1 }, acceleration: { x: 1, y: null, z: 1 } }), null);
});
t('eventTimeMs uses event.timeStamp, falls back to now for 0/missing/epoch', () => {
  assert.strictEqual(Core.eventTimeMs({ timeStamp: 1234.5 }, 99), 1234.5);
  assert.strictEqual(Core.eventTimeMs({ timeStamp: 0 }, 99), 99);
  assert.strictEqual(Core.eventTimeMs({}, 99), 99);
  assert.strictEqual(Core.eventTimeMs({ timeStamp: 1730000000000 }, 99), 99);
});
t('toUs gives integer microseconds since Start', () => {
  assert.strictEqual(Core.toUs(1010.0123, 1000), 10012);
  assert.ok(Number.isInteger(Core.toUs(1000.33333, 1000)));
});

// Fake event stream: 5 events ~10 ms apart, then a 50 ms gap, out of nothing else.
const startMs = 1000;
const fake = [
  [1000.0, 0.1, 0.2, 9.81], [1010.0, 0.123456789, -0.2, 9.8], [1020.5, 0, 0, 9.7],
  [1030.0, -1.5, 2.25, 9.9], [1080.0, 0.3, 0.1, 9.8]
].map(([ms, x, y, z]) => ({ t_us: Core.toUs(ms, startMs), ax: x, ay: y, az: z }));

t('buildCsv: exact header, one row per event, 6 decimals, no resampling', () => {
  const csv = Core.buildCsv(fake);
  const lines = csv.trimEnd().split('\n');
  assert.strictEqual(lines[0], 't_us,ax,ay,az');
  assert.strictEqual(lines.length, 1 + fake.length);
  assert.strictEqual(lines[1], '0,0.100000,0.200000,9.810000');
  assert.strictEqual(lines[2], '10000,0.123457,-0.200000,9.800000');
  assert.strictEqual(lines[3], '20500,0.000000,0.000000,9.700000');
  assert.strictEqual(lines[5], '80000,0.300000,0.100000,9.800000');
  console.log('--- SYNTHETIC CSV ---\n' + csv + '--- end SYNTHETIC CSV ---');
});
t('stats: rate = (n-1)/duration, median dt, max gap', () => {
  const s = Core.stats(fake);
  assert.strictEqual(s.n_samples, 5);
  assert.strictEqual(s.duration_s, 0.08);
  assert.strictEqual(s.measured_rate_hz, 4 / 0.08);
  assert.strictEqual(s.median_dt_ms, (10 + 10.5) / 2);   // dts 10, 10.5, 9.5, 50 -> sorted 9.5,10,10.5,50
  assert.strictEqual(s.max_gap_ms, 50);
});
t('stats: 0 and 1 samples give NaN, not made-up values', () => {
  assert.ok(Number.isNaN(Core.stats([]).measured_rate_hz));
  const one = Core.stats([fake[0]]);
  assert.strictEqual(one.duration_s, 0);
  assert.ok(Number.isNaN(one.measured_rate_hz) && Number.isNaN(one.max_gap_ms));
});
t('buildMeta: required keys in key=value form', () => {
  const meta = Core.buildMeta(fake, {
    session_id: 'SYNTHETIC_test', device_model: 'Fake\nModel', user_agent: 'FakeUA/1.0',
    start_time_iso: '2026-11-04T00:00:00.000Z', accel_sources: { includingGravity: 5 },
    n_events_without_data: 2, synthetic: true
  });
  const kv = Object.fromEntries(meta.split('\n').filter((l) => l && !l.startsWith('#')).map((l) => {
    const i = l.indexOf('='); return [l.slice(0, i), l.slice(i + 1)];
  }));
  for (const k of ['sensor', 'source', 'session_id', 'device_model', 'user_agent', 'start_time_iso',
    'n_samples', 'duration_s', 'measured_rate_hz', 'median_dt_ms', 'max_gap_ms', 'accel_source', 'units']) {
    assert.ok(k in kv, 'missing key ' + k);
  }
  assert.strictEqual(kv.sensor, 'phone_accelerometer');
  assert.strictEqual(kv.source, 'phone (not ESP32)');
  assert.strictEqual(kv.device_model, 'Fake Model');           // newline cannot break the format
  assert.strictEqual(kv.n_samples, '5');
  assert.strictEqual(kv.measured_rate_hz, '50.000');
  assert.strictEqual(kv.max_gap_ms, '50.000');
  assert.strictEqual(kv.accel_source, 'includingGravity');
  assert.strictEqual(kv.units, 'm/s^2');
  assert.ok(meta.startsWith('# SYNTHETIC TEST DATA'));
  console.log('--- SYNTHETIC meta.txt ---\n' + meta + '--- end SYNTHETIC meta.txt ---');
});
t('buildMeta: mixed sources reported as mixed; real recordings have no synthetic marker', () => {
  const meta = Core.buildMeta(fake, { accel_sources: { includingGravity: 3, acceleration: 2 } });
  assert.ok(meta.includes('accel_source=mixed'));
  assert.ok(!meta.includes('SYNTHETIC') && !meta.includes('synthetic='));
});
t('sanitizeSession', () => {
  assert.strictEqual(Core.sanitizeSession(' my run #1 '), 'my_run_1');
  assert.strictEqual(Core.sanitizeSession('', new Date(2026, 10, 5, 9, 8, 7)), 'phone_2026-11-05_090807');
});
console.log(`\n${passed} tests passed (SYNTHETIC data only)`);
