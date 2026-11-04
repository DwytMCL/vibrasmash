# ESP32 recording format (input contract)

Status: Stage 8, 2026-10-21. No ESP32 firmware or real recording exists yet.
This contract is the target the firmware should write. If the firmware ends up writing
something different, this document and the importer change; the recording is never
massaged to fit.

## Principles

1. **Raw values only.** Files hold ADC counts and IMU register counts exactly as read.
   All unit conversion happens on the laptop, using parameters in `meta.txt`, so a
   wrong conversion can be fixed without re-recording.
2. **Original timestamps only.** Every row carries the time it was sampled, from the
   single ESP32 clock that serves both sensors (proposal, "Hardware architecture").
   The importer never resamples, interpolates, re-orders or deletes samples.
3. **The two streams are asynchronous.** Piezo (nominal 20,000 samples/s) and IMU
   (nominal 200 samples/s) are separate files with separate time vectors. They are
   aligned only by timestamp: a window "250 ms before onset" selects IMU rows whose
   `t_us` falls in that interval. IMU timing resolution is one IMU sample period,
   about 5 ms, and results never claim better (proposal, "Sampling and signal
   preparation").
4. **Problems are flagged, not fixed.** Gaps, duplicates, backwards time, rate
   mismatch and clipping are written to a QC report and carried as per-sample and
   per-shot flags.

## Session folder

```
data/raw/<session_id>/
  meta.txt     key = value settings for this session
  piezo.csv    piezo ADC samples
  imu.csv      IMU samples
```

### piezo.csv

| Column | Type | Required | Meaning |
| --- | --- | --- | --- |
| `t_us` | integer | yes | Sample time in microseconds on the ESP32 clock |
| `adc_raw` | integer | yes | ADC count, 0 to 2^bits − 1 |
| `adc_mv` | number | no | Millivolts from the ESP-IDF ADC calibration API, if the firmware applies it |
| `record_id` | integer | for triggered records | Which buffered event record the row belongs to |

The ESP32 continuous ADC driver delivers samples in DMA frames, and the firmware may
know only each frame's time. In that case it writes `t_us` = frame time + index /
nominal rate and sets `piezo_timestamp_mode = frame_derived` in `meta.txt`. The
importer then reports per-frame timing (frame-to-frame spacing) rather than treating
derived per-sample times as measurements. With `per_sample`, every `t_us` is treated
as measured.

### imu.csv

| Column | Type | Required | Meaning |
| --- | --- | --- | --- |
| `t_us` | integer | yes | Time of the I²C read, ESP32 clock |
| `gx_raw`, `gy_raw`, `gz_raw` | integer | yes | Gyroscope registers, signed 16-bit |
| `ax_raw`, `ay_raw`, `az_raw` | integer | yes | Accelerometer registers, signed 16-bit |
| `record_id` | integer | for triggered records | Matches `piezo.csv` |

### meta.txt

One `key = value` per line; `#` starts a comment. Unknown keys are kept and copied into
the run log.

| Key | Example | Required | Used for |
| --- | --- | --- | --- |
| `format_version` | 1 | yes | Importer compatibility |
| `session_id` | 2026-11-03_ref_01 | yes | Output naming |
| `session_type` | reference / controlled / movement / stroke / pilot / noise / synthetic | yes | Keeps pilot, reference and evaluation data separate |
| `split` | pilot / tuning / evaluation / test | yes | Evaluation scripts refuse non-evaluation data |
| `condition` | low / middle / high | for controlled | Release-angle condition |
| `participant` | P01 | for stroke | Codes only, never names (proposal) |
| `block` | 1 | for stroke | Ten-shot block number |
| `recording_mode` | triggered / continuous | yes | How records are segmented |
| `piezo_fs_nominal_hz` | 20000 | yes | Rate check only |
| `imu_fs_nominal_hz` | 200 | yes | Rate check only |
| `piezo_timestamp_mode` | per_sample / frame_derived | yes | How piezo timing is judged |
| `adc_bits` | 12 | yes | Clipping limits, conversion |
| `adc_vref_mv` | 3300 | if no `adc_mv` | Linear conversion fallback |
| `adc_attenuation_db` | 11 | yes | Recorded for traceability |
| `afe_bias_mv` | 1650 | yes | Expected bias (checked against measured) |
| `afe_gain` | 10 | yes | Recorded; changes invalidate the reference |
| `gyro_range_dps` | 2000 | yes | Scale and clipping (proposal: ±2,000 °/s) |
| `accel_range_g` | 16 | yes | Scale and clipping (proposal: ±16 g) |
| `mount_id` | shaft-A | yes | Changes invalidate the reference |
| `racket_id` | R1 | yes | Changes invalidate the reference |
| `clock_source` | esp_timer | yes | Wrap-around check |
| `pre_trigger_s` | 0.300 | for triggered | Actual firmware pre-trigger length, used for the bias estimate (falls back to the config's 300 ms) |
| `synthetic` | true | synthetic files only | Marks generated test data; real recordings omit it or set false |

## Unit conversions (all on the laptop)

| Quantity | Formula | Notes |
| --- | --- | --- |
| Piezo voltage at the ADC pin | `adc_mv / 1000` if present, else `adc_raw × adc_vref_mv / (2^adc_bits − 1) / 1000` | The linear fallback ignores the ESP32 ADC's known non-linearity; the run log says which was used |
| Bias-removed piezo signal | voltage − bias estimate | Units: V at the ADC pin. Not converted to sensor voltage or force; the index is relative (proposal) |
| Angular rate | `g*_raw / S_g` deg/s, S_g = 16.4 LSB/(°/s) at ±2,000 °/s | MPU-6050 datasheet table (131, 65.5, 32.8, 16.4 for ±250 to ±2,000 °/s), in `src/util/vs_imu_sensitivity.m`; any other range is an error |
| Acceleration | `a*_raw / S_a` g, S_a = 2048 LSB/g at ±16 g | Datasheet table (16384, 8192, 4096, 2048 for ±2 to ±16 g); recorded, not used by the two proposal outputs |
| Time | `t_us / 1e6` s | `uint32` microsecond counters wrap after about 71.6 min; a wrap is flagged, not unwrapped silently |

## Reading and validation (Stage 3)

Two steps with different rules:

- `vs_read_recording(folder)` **errors** only when the files cannot be interpreted at all:
  a missing file, a missing required `meta.txt` key or CSV column, a key given twice,
  non-numeric text in a CSV, an unsupported `format_version`, or an unsupported sensor
  range. Columns may be in any order, and Windows (CRLF) line endings are accepted. Rows
  are never sorted, resampled, interpolated or removed. Empty cells become NaN.
- `vs_validate_recording(rec, cfg)` **flags** data-quality problems and changes nothing.
  `scripts/check_recording.m` prints its report for one folder.

Checks are made per stream and per record. In triggered mode, the time between records
is not counted as a gap.

| Check | Rule | Flag code |
| --- | --- | --- |
| Backwards time | Δt < 0 within a record | `<stream>_backwards_time` |
| Duplicate time | Δt = 0 within a record | `<stream>_duplicate_time` |
| Clock wrap | Δt < −2^31 µs (a `uint32` microsecond counter rolled over) | `<stream>_clock_wrap` |
| Gaps | Δt > `sampling.gap_factor` (1.5) × median Δt; missing samples estimated as round(Δt / median Δt) − 1 | `<stream>_gaps` |
| Missing % | missing / (present + missing) ≥ the proposal's 1% target | `<stream>_missing_above_target` |
| Measured rate | 1e6 × (number of normal intervals) / (sum of normal intervals in µs), where normal means positive and not a gap. Used for all later calculations | `<stream>_rate_mismatch` if more than `sampling.rate_tolerance_pct` (2%) from nominal |
| Interval spread | 5th, 50th and 95th percentile of normal intervals | Reported only |
| Too few samples | A record with no positive interval | `<stream>_record_too_few_samples` |
| Empty values | NaN in any column | `piezo_nan_values`, `imu_nan_values` |
| ADC clipping | `adc_raw` ≤ margin or ≥ 2^bits − 1 − margin (`qc.adc_clip_margin_counts`) | `piezo_clipped` |
| IMU clipping | Any axis at −32768 or +32767 (± `qc.imu_clip_margin_counts`) | `imu_gyro_clipped`, `imu_accel_clipped` |
| Record length | Duration < 250 ms + 2,048 / measured piezo rate, the shortest record that can hold both feature windows | `record_too_short` |
| IMU coverage | The IMU record must start and end within 1.5 IMU periods of its piezo record | `imu_does_not_cover_piezo` |
| Record ids | Both files must contain the same record ids | `record_ids_mismatch` |
| Bias | Median piezo voltage vs `afe_bias_mv` | Reported only |
| Synthetic data, frame-derived timestamps | From `meta.txt` | Notes, not flags |

The validator also returns per-sample masks: `clipped`, `after_gap`, `time_error` and
`nan`. Later stages use them to decide whether a feature window touches a flagged sample.
`qc.status` is `clean` or `flagged`. Accepting or rejecting a trial, and reporting the
reason, happens in later stages. Every flagged record stays in the outputs.

## Synthetic test fixtures

`scripts/make_synthetic_fixture.m` writes session folders in exactly this format so the
importer and later stages can be tested before real recordings exist. They are test
inputs only, never results, and are marked in four ways:

- the folder name starts with `synthetic_`
- `meta.txt` starts with a `SYNTHETIC TEST DATA` comment and has `synthetic = true`,
  `session_type = synthetic` and `split = test`
- a `synthetic_truth.csv` file lists every planted event (category, onset time, burst and
  swing parameters, record id), which real recordings never have
- the generator refuses to write inside `data/`, which holds real recordings only

The signal shapes (a decaying sinusoid for each impact and a Gaussian swing peak before it)
and all default amplitudes are arbitrary test values. They are not models of a real racket.
Events can be `contact`, `dry_swing` (swing, no burst), `handling` or `frame_tap` (small
burst, usually no swing). Detection tests use the non-contact categories as distractors.
The generator can also inject faults for validation tests: dropped samples, duplicated
timestamps, IMU timestamp jitter, an actual rate different from nominal, and ADC clipping.

Typical use, writing to a temporary folder:

```
spec = make_synthetic_fixture();     % default specification
spec.out_dir = tempdir;
spec.recording_mode = 'triggered';   % or 'continuous'
info = make_synthetic_fixture(spec); % info.folder is the session folder
```

### Session roles in synthetic fixtures (Stage 6)

`spec.synthetic_role` writes `synthetic_role = reference` (or `controlled`, `stroke`, ...)
to `meta.txt`, and `spec.meta_extra` adds keys such as `condition` or `block`. The keys
that carry the synthetic labelling (`synthetic`, `session_type`, `split`, `session_id`,
`format_version`, `recording_mode`) cannot be overridden. `vs_session_role` uses
`synthetic_role` only when `synthetic = true`. Triggered fixtures also write
`pre_trigger_s`, as the firmware should.

## Ground-truth annotation file (Stage 7)

One CSV per session (or one for several), from the phone video and the operator's trial
log. The proposal says this establishes event counts and categories and does not
validate millisecond timing.

```
action_id,category,t_start_s,t_end_s,session,split
1,contact,12.40,12.75,2026-11-05_mov_01,evaluation
2,dry_swing,15.10,15.60,2026-11-05_mov_01,evaluation
```

| Column | Meaning |
| --- | --- |
| `action_id` | Integer, unique within its session |
| `category` | `contact`, `dry_swing`, `handling` or `frame_tap` |
| `t_start_s`, `t_end_s` | Interval of the action on the ESP32 clock, in seconds (`t_us` / 1e6 of the recording, not seconds from the start of the file) |
| `session` | The `session_id` from `meta.txt` |
| `split` | Must be `evaluation`; `test` is accepted only for synthetic fixtures |

Intervals in one session must not overlap. `vs_read_annotations` rejects overlaps, unknown
categories, reversed intervals and repeated ids. Every performed action must be listed,
including ones the ESP32 did not record, so missed impacts and correct rejections are
counted (`docs/settings_provenance.md`, section 4).
`scripts/make_synthetic_annotations.m` writes this file from a synthetic fixture's planted
events, for tests only.
