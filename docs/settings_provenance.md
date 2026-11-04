# Settings and methods: what comes from the proposal

Status: Stage 8 (complete software), 2026-10-21. Nothing in this document has been
tested on real ESP32 recordings or validated experimentally.

Every processing setting is defined once, in `config/default_config.m`, with one
of three sources:

- **proposal**: stated in `VibraSmash_Proposal.docx`. Tests pin these values, so a
  silent change fails the test suite (`tests/unit/test_default_config.m`).
- **provisional**: an engineering choice for this software where the proposal
  gives no value. It may be revised during pilot testing, but each change goes
  into `docs/settings_log.md` and all settings are frozen before evaluation data is
  processed (proposal, "Research design").
- **pilot**: has to be measured from pilot recordings. It stays empty until then, and
  code that needs it refuses to run.

The tables at the end are generated from the config by
`scripts/print_settings_table.m`, so they cannot drift from the code.

## 1. Points where the proposal is reproduced exactly

- Piezo: bias removal, then a 4th-order Butterworth high-pass at 80 Hz and a 4th-order
  Butterworth low-pass at 2 kHz. Gyro: a 4th-order Butterworth low-pass at 20 Hz on each axis.
  "The quoted orders describe each single pass", so each filter is designed with
  `butter(4, ...)` and applied forward and backward. The squared response gives -6 dB at
  the cutoff, and Stage 4 tests check this. The high-pass and low-pass are kept as two
  separate 4th-order designs, not merged into one 8th-order band-pass.
- Forward-backward filtering is applied "on a padded event record; short windows will not be
  filtered independently without padding". `filtfilt` itself extends the signal by only
  3 × (filter length − 1) = 12 samples for these filters. That is 0.6 ms at 20 kHz, far too
  short for an 80 Hz high-pass to settle. This was confirmed in the Octave signal package
  source; MATLAB's documented algorithm uses the same length, which Stage 4 tests will check
  in MATLAB. The pipeline therefore adds its own padding first. The method and length are
  provisional.
- Detection uses a 5 ms moving RMS envelope. The threshold is median(background) +
  6 × MAD, with a floor above the measured electronics noise, followed by a 150 ms refractory
  interval. "Six median absolute deviations" is read as the unscaled MAD. The common
  1.4826 normal-consistency factor is not applied, because the proposal does not mention it.
- Impact RMS is RMS = sqrt((1/N) Σ x[n]²) over the first 100 ms after the onset.
  The intensity index is I = 100 × RMS / RMS_ref.
- Angular speed is sqrt(gx² + gy² + gz²), and the feature is its peak in the 250 ms before
  the onset.
- The spectrum uses a 2,048-sample Hann-windowed FFT. At 20 kHz that is 102.4 ms with 9.77 Hz
  bins, and it is treated as an exploratory diagnostic only.
- CV = 100 × sample standard deviation / mean. It is reported separately for impact RMS and
  for pre-impact peak angular speed, using valid shots only.
- Detection evaluation reports TP, FP, missed impacts, precision, recall and F1 for
  piezo-only and IMU-confirmed detection on the same held-out trials. The targets are
  precision and recall of at least 0.90, controlled middle-condition RMS CV of 15% or less,
  and less than 1% missing samples. These are reported against and never used for tuning.
- The 20,000 and 200 samples/s rates are **nominal**. Every calculation uses the rate
  measured from the recording's own timestamps. The nominal rate is used only to flag a
  mismatch.

## 2. Minimum of eight valid shots (your item 2)

**This is stated in the proposal**, not added by me. Under "Data handling and reporting" it
says: "A block with fewer than eight valid shots will be marked insufficient for the planned
ten-shot summary." It is kept as `consistency.min_valid_shots = 8`, source *proposal*, and it
can be changed in the config. A block below the minimum still has its CVs calculated and
exported, but it is labelled `insufficient` and kept out of any summary presented as a
ten-shot result. This means the proposal's requirement that "attempted, accepted, and
rejected counts will all be reported with reasons" still applies.

The proposal does not say why the minimum is eight. My methodological reading: CV from fewer
than about eight values has a wide sampling spread, so a block that lost three or more of its
ten planned shots should not be compared with complete blocks. This is my interpretation,
not the proposal's.

## 3. FFT window alignment and completeness (your item 3)

- **Alignment.** The window covers samples onset … onset + 2047, where onset is the detected
  onset sample of the piezo record. This is the "early post-impact spectrum". The zero offset
  is provisional (`spectrum.start_offset_s = 0`).
- **Length.** It is always exactly 2,048 samples. The duration is 2048 / fs_measured, so it is
  102.4 ms only if the measured rate is exactly 20 kHz. Bin k is labelled
  f_k = k × fs_measured / 2048 for k = 0 … 1024. The amplitude is one-sided and divided by
  the window's coherent gain (sum of the Hann weights / 2048), so a sine of amplitude A reads
  A when it falls on a bin centre.
- **Relation to the record.** The ESP32 keeps about 200 ms after its trigger (proposal), which
  is 4,000 samples at 20 kHz. The laptop onset is close to the ESP32 trigger but not
  identical, so the code checks the actual sample count and does not assume it.
- **Incomplete window.** If fewer than 2,048 samples exist after the onset, no spectrum is
  computed. The shot is flagged `fft_incomplete`, and its RMS and other features are still
  reported if their own windows are complete. There is no silent zero-padding.
- **Contaminated window.** The spectrum is flagged and excluded from spectral plots and
  summaries when the window contains:
  - a timestamp gap (missing samples), flagged `fft_gap`
  - ADC samples at the clipping limits, flagged `fft_clipped`
  - padding samples from the filter step, flagged `fft_padding`. *Stage 6 note:* the
    spectrum is taken from the bias-removed signal (section 8), which is not filtered,
    so this flag applies to the RMS window (`rms_padding`, a sample inside the 50 ms
    filter edge zone) and to the spectrum only if `spectrum.signal = filtered`.

  A second impact cannot be detected inside the window, because the 150 ms refractory
  interval is longer than the 102.4 ms window. Even so, a second envelope threshold crossing
  inside the window is flagged `fft_second_event` rather than ignored.
- The same completeness and contamination rules apply to the 100 ms RMS window and the
  250 ms pre-impact gyro window. Each window carries its own flag, so a shot can have a valid
  RMS but no valid spectrum.

## 4. Event-matching algorithm (your item 4)

The proposal states that ground truth comes from "phone video and the operator's trial log",
that this establishes event counts and action categories, and that it "will not validate
millisecond impact timing". The matching therefore works on **annotated action intervals**,
not on exact impact times.

**Annotation input.** There is one row per performed action:
`action_id, category, t_start_s, t_end_s, session, split`.

- `category` is one of `contact`, `dry_swing`, `handling` or `frame_tap`.
- Times are in the ESP32 clock, mapped from video by the operator.
- `split` must be `evaluation` for the evaluation script to accept the file.

Intervals must not overlap. Overlapping intervals are rejected at validation as an annotation
error and are never resolved silently.

**Matching, with tolerance τ = `evaluation.match_tolerance_s` (provisional, 100 ms).**

1. A detection at time d is a *candidate* for action a if a.t_start − τ ≤ d ≤ a.t_end + τ.
2. The pair's distance is 0 if d lies inside [t_start, t_end]. Otherwise it is the distance to
   the nearer edge.
3. Only `contact` actions can produce a true positive. Contact–detection pairs are assigned
   one-to-one: sort all candidate pairs by distance, then by detection time, and accept each
   pair whose action and detection are both still unassigned. This order is fixed, so the
   result is reproducible.
4. **TP** = matched contacts. **FN (missed impacts)** = unmatched contacts. This includes
   contacts that fall in a rejected or missing record, which are counted as missed rather
   than dropped. **FP** = every unmatched detection.
5. Each FP is labelled with the reason it was not matched:
   - `in_dry_swing`, `in_handling` or `in_frame_tap` if it lies within τ of that action
   - `duplicate` if it is a second detection inside an already-matched contact
   - `spurious` if it is outside every action
6. A non-impact action with no detection is a **correct rejection**. These are reported per
   category but do not enter precision, recall or F1, which are defined over impacts only.
7. Precision = TP / (TP + FP), recall = TP / (TP + FN), F1 = 2PR / (P + R). An undefined
   ratio, such as zero detections, is reported as undefined, not as 0 or 1.

**Ambiguity.** Because intervals cannot overlap, the only ambiguous case is a detection that
lies within τ of two adjacent actions. A contact is preferred over a non-contact only when the
detection lies *inside* the contact's interval. Otherwise the smaller distance wins, and if the
distances are equal the result is reported as `ambiguous` in the output. Every ambiguous case
is listed so it can be checked against the video.

**Why τ = 100 ms is provisional.** Ordinary phone video at 30 frames/s has about 33 ms frame
spacing. Aligning video with the ESP32 clock adds an offset that has not been measured yet.
τ should be fixed after pilot annotation and before evaluation. A setting much larger than
the spacing between actions would let one detection reach a neighbouring action, so the
evaluation script will warn if τ exceeds half the smallest gap between annotated actions.

Both detectors (piezo-only and IMU-confirmed) are matched against the same annotation file and
reported side by side. Actions without an ESP32 record are still counted. A dry swing that
never triggered the ESP32 is a correct rejection, and a contact with no record is a missed
impact. This depends on the trial log listing every action.

## 5. Reference impacts (your item 5)

From the proposal: RMS_ref is "the median response from ten controlled reference impacts made
before the human demonstration". Under "Controlled impact repeatability" it adds: "Ten separate
middle-condition impacts will establish the reference response; pilot tuning records will be
kept separate."

Implementation rules:

- Reference impacts are their own session folders, with `session_type = reference` and
  `condition = middle` in `meta.txt`. They are processed with the same frozen settings.
- RMS_ref is the median of the reference shots' 100 ms RMS values. Only valid shots count, and
  `features.reference_impact_count = 10` are expected.
  - Fewer than 10 valid reference shots: RMS_ref is still computed and the shortfall is
    recorded in every output that uses it.
  - No reference session: the intensity index is left empty. RMS is still reported.
- Every run log records the reference files, their hashes, the shots used, and RMS_ref, so the
  normalisation can be reproduced.
- The reference is tied to the setup. If the gain, mount or racket changes (recorded in
  `meta.txt`), the code refuses to apply an old reference to the new data.
- **The old `vibra_results.csv` is never used as a reference.** Its index divides by the median
  of its own nine shots (0.06875 for shot 3), which is not the proposal's method. That file is
  used only for an arithmetic check of the index and CV formulas and as a column-layout
  reference.

## 6. Preprocessing decisions made in Stage 4

- **Filters use the measured rate.** `vs_design_filters` designs each Butterworth filter at
  the sampling rate measured by the validator, so a 19 kHz recording still gets its cutoffs
  at 80 Hz and 2 kHz.
- **Filtering never crosses a discontinuity.** Each record is split into runs at gaps,
  timestamp errors and NaN samples. Each run is padded by odd reflection
  (`filter.padding_s` = 50 ms per side, capped at the run length) and filtered on its own.
  Samples within 50 ms of a run edge are marked `near_edge`. Runs too short for `filtfilt`
  are left as NaN and reported.
- **Bias.** Triggered records use the median of the pre-trigger samples, excluding the
  last 20 ms before the trigger. Continuous recordings have no trigger, so they use the
  median of the whole record. This is a new provisional setting,
  `preprocess.bias_method_continuous`, logged in `settings_log.md`. The pre-trigger length
  comes from `meta.txt`'s optional `pre_trigger_s`, or from `record.pre_trigger_s` (300 ms)
  when that key is absent.
- **No gyroscope offset removal.** The proposal filters the gyro but does not remove a
  zero-rate offset. The MPU-6050 can have an offset of several deg/s at rest, which adds to
  the angular-speed magnitude. Nothing is subtracted unless that is agreed, because it would
  change the proposal's feature.

## 7. Detection decisions made in Stage 5

These describe how the software behaves on synthetic test signals. They are not
measurements.

- **Onset definition.** The onset is the first sample where the 5 ms RMS envelope of the
  filtered piezo signal reaches the threshold after being below it. Only crossings outside
  filter edge zones count.
- **Envelope alignment changed to trailing** (provisional, logged). A centred window
  starts to include a burst half a window (2.5 ms) before the burst begins.
- **Zero-phase filtering makes onsets early.** The proposal requires forward-backward
  filtering. With an 80 Hz high-pass, that spreads a sharp burst start backwards in time.
  On the default synthetic contacts (250–300 mV bursts, 5 mV threshold), the detected onset
  was 0.9 to 1.8 ms **before** the planted onset across 20 random seeds. A smaller 80 mV
  burst was detected 0.1 ms after its onset. The 100 ms RMS window therefore starts slightly
  early. This is a property of the specified filter, not something the software corrects.
- **Threshold per record.** The background for a triggered record is its pre-trigger part,
  excluding the last 20 ms. For a continuous recording it is the whole record. Samples in
  filter edge zones are never background.
- **Edge zones.** A crossing within 50 ms of a run edge is listed in
  `det.edge_candidates`, not counted, and still starts a refractory interval. Odd-reflection
  padding of a noisy run can leave a small high-pass transient there; one synthetic seed
  produced such a crossing at a record start.
- **Refractory limit.** The 150 ms interval runs from each onset. A burst that stays above
  threshold for longer than 150 ms can be counted twice. A synthetic burst with a 100 ms
  decay was counted twice, and one with a 30 ms decay once. Real ringing durations need
  checking in pilot recordings.
- **Distractors.** On the seeded distractor fixture (6 contacts with swings, 3 handling bumps
  at 40 mV with no swing, 2 dry swings, 2 bumps at 2 mV), piezo-only detection found the
  6 contacts **and** the 3 handling bumps. The gyro rule kept only the 6 contacts. Dry swings
  and the 2 mV bumps were never detected. This is why the proposal evaluates both rules.
- **Two pilot values are still unset:** `detect.noise_floor_threshold`, which detection
  refuses to run without, and `detect.swing_confirm_threshold_dps`. Tests use 5 mV and
  60 deg/s, chosen for the synthetic noise level only. These must not be copied into the
  config.
- **Stationary tests** (`session_type` = reference or controlled) never use the gyro rule,
  as the proposal says.
- `vs_angular_speed` and `vs_preimpact_peak` (module 5) were built in this stage because
  gyro confirmation needs them. Stage 6 reuses them for the pre-impact feature.

## 8. Feature decisions made in Stage 6

These describe how the software behaves on synthetic test signals. They are not
measurements.

- **RMS window.** RMS uses the filtered piezo signal (the proposal's pipeline order:
  bias, filters, detection, features) over round(0.1 × measured rate) samples starting at
  the onset sample, so 2,000 samples at exactly 20 kHz. On the default synthetic contacts
  the result was within 3% of the planted signal's analytic RMS, A·sqrt(τ / 4T).
- **Spectrum signal: bias-removed, not filtered** (new provisional setting
  `spectrum.signal`, logged). The proposal says the spectrum helps "inspect ringing,
  noise, and saturation artifacts". The 2 kHz low-pass would hide noise and clipping
  harmonics between 2 kHz and the 3 kHz analog filter, so the FFT is taken before the
  digital filters. Set `spectrum.signal = filtered` to use the filtered signal instead.
- **Hann form: periodic** (new provisional setting `spectrum.hann_form`, logged). This is
  the usual form for spectral analysis. The amplitude is divided by the coherent gain,
  and the reported peak frequency skips bins 0 and 1, because a Hann window spreads any
  remaining DC offset into those two bins.
- **Second event inside a window** (new provisional setting
  `features.second_event_ratio = 2`, logged). Section 3 promised to flag any second
  upward threshold crossing inside the RMS or FFT window. On synthetic data the decaying
  tail of a *single* burst hovers at the threshold and re-crossed it inside the 100 ms
  window on 6 of 10 seeds, which would have invalidated most good shots. A re-crossing now
  counts as a second event only if the envelope then reaches 2 × the threshold within
  one envelope window (5 ms). A second planted burst 60 ms after the first is still flagged.
  The proposal's refractory interval already treats ringing as one event, so this keeps
  the same intent. Pilot recordings should confirm the ratio.
- **Pre-impact window near the filter edge is a note, not a fault.** A triggered record
  keeps 300 ms before the trigger, and the 250 ms window then starts about 50 ms into
  the record, right at the gyro filter's edge zone. Treating that as contamination would
  invalidate every triggered shot, so it is reported as `preimpact_near_edge` only. Gaps,
  NaN, clipping and unfiltered samples do invalidate the window.
- **A gap within 50 ms after an onset loses the detection.** The gap splits the record,
  which puts the onset inside a filter edge zone, so the crossing is listed in
  `edge_candidates` and not counted. In an evaluation this shows up as a missed impact,
  never silently. The run log counts edge candidates per session.
- **Values versus validity.** A complete but contaminated window still reports its value
  with flags, and `*_valid` is false. An incomplete window gives no value. Only valid
  values enter RMS_ref, the index and the CVs.
- **Reference.** Reference sessions must have role `reference` and `condition = middle`,
  and all must share one setup (`afe_gain`, `mount_id`, `racket_id`). If there are more
  than 10 valid reference shots, all of them are used and the status is `excess`. If
  there are fewer, the status is `shortfall`. Either way the status is written next to
  every index value. Applying a reference to a session from another setup is an error.
- **Synthetic roles.** Synthetic fixtures stay `session_type = synthetic` and
  `split = test`. A `synthetic_role` key lets tests act as reference, controlled or stroke
  sessions. Real recordings ignore that key.

## 9. Consistency and evaluation decisions made in Stage 7

- **One block = one session folder** (new provisional setting `consistency.block_key`).
  The proposal's blocks are one ten-shot controlled run or one volunteer block, so each
  is recorded as its own session.
- **Each CV uses that feature's valid shots.** A shot with a clean RMS window but an
  incomplete swing window counts for the RMS CV only. The two CVs can therefore use
  different shot counts. Both counts are exported, and each feature gets its own
  sufficient/insufficient status against the 8-shot minimum.
- **Shots are accepted detections.** By default every piezo detection is a shot. With
  `detect.swing_confirm_enabled = true`, detections the gyro rule rejects are kept in
  `shots.csv` as `rejected_not_swing_confirmed` and counted as rejected.
- **Stationary blocks** (reference, controlled) get no angular-speed CV; their status is
  `stationary_session`. The proposal does not report a swing for a pendulum impact.
- **Middle-condition target.** For controlled middle blocks, the RMS CV is compared with
  the 15% target and the result is written as a note. It is never used to change a
  setting.
- **Evaluation** follows section 4 exactly. F1 is 2PR / (P + R) and is undefined (an empty
  cell) when P or R is undefined, or when both are 0. Annotation files may be split across
  sessions; action ids must be unique within a session. `run_vibrasmash` scores only the
  sessions that have annotations, and lists the rest as not scored.
- Not implemented, and listed as open: a rank correlation across release conditions
  (the proposal says "if useful"), and a loose-mounting flag (this needs an operator
  entry; nothing in the signals marks it).

## 10. Outputs made in Stage 8

`run_vibrasmash` writes one folder per run, named with the date, the time and a label.
It starts with `synthetic_` when any input is synthetic. The folder holds:

- `README.txt`
- `run_log.txt`: every setting with its source and any change from the default, every
  input file with its size, date and SHA-256, the reference and the shots it used, the
  QC per session, warnings, and processing times
- `shots.csv`, `reference_shots.csv`, `blocks.csv`, `qc.csv` and `spectra/<session>.csv`
- with annotations: `evaluation_summary.csv`, `evaluation_detections.csv` and
  `evaluation_actions.csv`
- `plots/<session>.png` (the proposal's display panels) and `plots/blocks.png`
  (individual-shot plots and block CVs)

Every CSV row has a `data_source` column (`real` or `SYNTHETIC`), and every plot title
and log of a synthetic run says so. Undefined values are empty cells, never 0. The
processing time per session is recorded for the proposal's one-second display target.
It is a software timing on the computer used, not a hardware result.

## 11. Generated settings table

### Source: proposal (26 settings)

| Setting | Value | Note |
| --- | --- | --- |
| `sampling.piezo_fs_nominal_hz` | 20000 | Proposed piezo ADC rate; must be verified against real recordings |
| `sampling.imu_fs_nominal_hz` | 200 | Proposed IMU rate; must be verified against real recordings |
| `sampling.missing_target_pct` | 1 | Objective target: less than 1% missing samples in accepted trials (reported, not used to drop data) |
| `record.pre_trigger_s` | 0.3 | Approximately 300 ms retained before a candidate impact |
| `record.post_trigger_s` | 0.2 | Approximately 200 ms retained after a candidate impact |
| `filter.piezo_hp_cutoff_hz` | 80 | Butterworth high-pass on piezo signal |
| `filter.piezo_hp_order` | 4 | Order per pass (proposal: quoted orders describe each single pass) |
| `filter.piezo_lp_cutoff_hz` | 2000 | Butterworth low-pass on piezo signal |
| `filter.piezo_lp_order` | 4 | Order per pass |
| `filter.gyro_lp_cutoff_hz` | 20 | Butterworth low-pass on each gyroscope axis |
| `filter.gyro_lp_order` | 4 | Order per pass |
| `filter.zero_phase` | true | Forward-backward filtering of the padded event record |
| `detect.envelope_window_s` | 0.005 | Moving RMS envelope length |
| `detect.threshold_mad_multiplier` | 6 | Threshold = median background envelope + 6 x MAD (unscaled MAD) |
| `detect.refractory_s` | 0.15 | Refractory interval after each detected onset |
| `features.rms_window_s` | 0.1 | RMS over the first 100 ms after detected onset |
| `features.reference_impact_count` | 10 | RMS_ref = median of ten controlled middle-condition reference impacts |
| `features.intensity_scale` | 100 | I = 100 x RMS / RMS_ref |
| `features.preimpact_window_s` | 0.25 | Peak angular-speed magnitude during the 250 ms before impact |
| `spectrum.nfft` | 2048 | Hann-windowed FFT length (102.4 ms at 20 kHz, 9.77 Hz bins) |
| `spectrum.window` | hann | Window type |
| `consistency.min_valid_shots` | 8 | A block with fewer than eight valid shots is marked insufficient for the planned ten-shot summary |
| `consistency.planned_block_size` | 10 | Ten shots per controlled condition run and per volunteer block |
| `evaluation.target_precision` | 0.9 | Objective target (reported against, never used to tune) |
| `evaluation.target_recall` | 0.9 | Objective target (reported against, never used to tune) |
| `evaluation.target_middle_rms_cv_pct` | 15 | Controlled repeatability target for the middle release condition |

### Source: provisional (19 settings)

| Setting | Value | Note |
| --- | --- | --- |
| `sampling.rate_tolerance_pct` | 2 | Flag a recording whose measured rate differs from nominal by more than this |
| `sampling.gap_factor` | 1.5 | An interval longer than this multiple of the median interval counts as missing samples |
| `preprocess.bias_method` | median_pre_trigger | Proposal says 'remove the recorded bias'; method is not specified |
| `preprocess.bias_exclude_before_trigger_s` | 0.02 | Pre-trigger samples closer than this to the trigger are excluded from the bias estimate |
| `preprocess.bias_method_continuous` | median_record | Continuous recordings have no trigger; bias = median of each record (robust to sparse bursts) |
| `filter.padding_method` | odd_reflection | Proposal requires padding but does not specify the method |
| `filter.padding_s` | 0.05 | Padding length per side, capped at record length minus one sample |
| `detect.envelope_alignment` | trailing | Window alignment is not specified; a trailing window crosses the threshold just after the burst starts, a centered one up to half a window before it |
| `detect.background_source` | pre_trigger | Background envelope samples: pre-trigger segment of each record, or whole record if continuous |
| `detect.swing_confirm_enabled` | false | Default for single runs only; proposal makes confirmation optional and evaluates both rules |
| `features.second_event_ratio` | 2 | A re-crossing inside a feature window flags a second event only if the envelope then reaches this multiple of the threshold within one envelope window |
| `spectrum.start_offset_s` | 0 | Proposal says 'early post-impact spectrum'; window starts at the detected onset |
| `spectrum.signal` | bias_removed | Signal the FFT is taken from: bias_removed (shows content the 2 kHz low-pass would hide, such as noise and clipping artefacts) or filtered |
| `spectrum.hann_form` | periodic | Hann form: periodic (DFT-even, the usual choice for spectral analysis) or symmetric |
| `spectrum.display_max_hz` | 5000 | Upper limit of the plotted axis only; does not affect the calculation |
| `consistency.block_key` | session | One block = one session folder (one ten-shot run or volunteer block) |
| `evaluation.match_tolerance_s` | 0.1 | Detections within this margin of an annotated action interval may match it |
| `qc.adc_clip_margin_counts` | 2 | ADC samples within this many counts of 0 or full scale are flagged as clipped |
| `qc.imu_clip_margin_counts` | 0 | IMU raw values at -32768 or +32767 are flagged as clipped |

### Source: pilot (2 settings)

| Setting | Value | Note |
| --- | --- | --- |
| `detect.noise_floor_threshold` | (not set) | Minimum threshold above measured electronics noise; measured from a still-racket recording |
| `detect.swing_confirm_threshold_dps` | (not set) | Pre-impact gyro threshold, established from pilot dry swings and real strokes |
