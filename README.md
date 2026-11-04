# VibraSmash processing software (MATLAB)

Laptop-side DSP software for the VibraSmash academic proposal. It computes relative impact
intensity from a racket-mounted piezoelectric sensor, and shot-to-shot consistency from
impact RMS and pre-impact gyroscope angular speed.

**Status: all 8 stages are built.** The stages cover configuration, tests, synthetic
fixtures, reading and validating recordings, filtering, impact detection, features,
consistency and detection evaluation, and reports. Nothing in this repository has been
validated on real ESP32 recordings, and the ESP32 hardware has not been validated. All
test inputs are synthetic and labelled as such.

Stages 1 to 3 passed in MATLAB R2026b on Windows (61 / 61). Stage 5 ran 99 / 100 in
MATLAB, and the failing test was fixed afterwards. The full suite (147 tests) has passed
under GNU Octave only; see `docs/stage*_test_record.txt`.

## Quick start

Requires MATLAB R2019b+ with the Signal Processing Toolbox (see `docs/install.md`).
It also runs in GNU Octave with the signal package (`pkg install -forge control signal`);
`run_tests` detects which one it is running in.

1. `cd` to this folder in MATLAB.
2. Smoke test: `addpath scripts; smoke_test`
3. Tests: `run_tests`
4. See every output on synthetic data: `vs_setup; demo_synthetic`
   This writes `results/synthetic_<date>_<time>_demo/`. Every file there says SYNTHETIC,
   and none of its numbers is a result.

## Processing real recordings

1. Put session folders in `data/raw/` and reference sessions in `data/reference/`
   (format: `docs/data_format.md`). Annotation CSVs go in `data/annotations/`.
2. Measure the two pilot settings from pilot recordings: `detect.noise_floor_threshold`
   from a still-racket recording, and `detect.swing_confirm_threshold_dps` from dry swings
   and real strokes. Record them in `docs/settings_log.md` and freeze all settings before
   evaluation data is processed.
3. Run:

   ```matlab
   vs_setup;
   cfg = default_config();
   cfg.detect.noise_floor_threshold = 0.0;          % <- your measured value (V)
   cfg.detect.swing_confirm_threshold_dps = 0.0;    % <- your measured value (deg/s)
   opts.sessions = {'data/raw/2026-11-05_mov_01', 'data/raw/2026-11-05_ctrl_mid_1'};
   opts.reference = {'data/reference/2026-11-05_ref_01'};
   opts.annotations = {'data/annotations/2026-11-05_mov_01.csv'};
   opts.cfg = cfg;
   opts.label = 'movement_eval';
   run = run_vibrasmash(opts);
   ```

`scripts/check_recording.m` prints the QC report for one folder before a run.

## Layout

| Path | Contents |
| --- | --- |
| `config/default_config.m` | Every setting, with its source (proposal / provisional / pilot) |
| `src/io` | Reading and validating recordings |
| `src/preprocess` | Bias removal and Butterworth filters with padding |
| `src/detect` | Envelope, threshold, onsets, refractory interval, gyro confirmation |
| `src/features` | Impact RMS, spectrum, pre-impact peak, window checks, reference and index |
| `src/analysis` | `vs_process_session`, block CVs, annotations, detection evaluation |
| `src/report` | CSV writers, file hashes, plots, run log |
| `src/util` | Environment check, IMU sensitivity, session role, setup signature |
| `scripts/` | `run_vibrasmash.m` (main entry), `demo_synthetic.m`, `smoke_test.m`, `check_recording.m`, `make_synthetic_fixture.m`, `make_synthetic_annotations.m`, `print_settings_table.m` |
| `run_tests.m`, `vs_setup.m` | Test runner (MATLAB unit test framework) and path setup |
| `tests/unit`, `tests/integration` | Function-based MATLAB tests (`test_*.m`) |
| `data/` | Real recordings only (`raw/`, `reference/`, `annotations/`) |
| `results/` | Generated outputs, one folder per run |
| `docs/` | `settings_provenance.md` (every method decision), `data_format.md`, `install.md`, `settings_log.md`, `open_decisions.md`, test records |

## Rules this code follows

- Settings from the proposal are pinned by tests. Provisional settings are logged in
  `docs/settings_log.md` when they change, and are frozen before evaluation.
- Measured sampling rates are used for every calculation. Nominal rates are used only
  for checks.
- Raw counts and original timestamps are kept. Problems are flagged, never silently
  fixed or dropped. Rejected shots and records stay in the outputs, with reasons.
- Undefined values (a CV from fewer than two shots, precision with no detections) are
  written as empty cells, never as 0.
- Synthetic signals exist only for tests and are always labelled as synthetic. They are
  never reported as measurements.
