# Decisions made without Dwight, for review

Dwight asked for Stages 6 to 8 to be finished without stopping between stages
(2026-10-21). Where a choice was needed, the option closest to the proposal was
taken and logged. Each can be changed in `config/default_config.m` (logged in
`docs/settings_log.md`) or in the named function. None has been checked on real
recordings.

| # | Decision | What was done | Where |
| --- | --- | --- | --- |
| 1 | Which signal the FFT uses | Bias-removed, before the 2 kHz low-pass, so noise and clipping artefacts stay visible (the proposal's stated purpose). Can be switched to `filtered`. | `spectrum.signal` |
| 2 | Hann window form | Periodic | `spectrum.hann_form` |
| 3 | What counts as a second event inside a feature window | A threshold re-crossing that then reaches 2 × the threshold within 5 ms. Without this, single-burst tails were flagged on 6 of 10 synthetic seeds. | `features.second_event_ratio` |
| 4 | Pre-impact window touching the gyro filter edge zone | Note only (`preimpact_near_edge`), because the proposal's 300 ms pre-trigger puts every triggered window there | `vs_shot_features` |
| 5 | One consistency block | One session folder | `consistency.block_key` |
| 6 | Shots counted in each CV | Each feature's own valid shots, so the RMS CV and the swing CV can use different counts; both counts are exported | `vs_consistency` |
| 7 | Swing CV for stationary (reference, controlled) blocks | Not computed, status `stationary_session` | `vs_consistency` |
| 8 | More than 10 valid reference shots | All are used; status `excess` is written next to every index | `vs_reference_rms` |
| 9 | Sessions without annotations in a run with annotations | Not scored, and listed in the warnings | `run_vibrasmash` |
| 10 | F1 when precision and recall are both 0 | Undefined (empty), following the formula 2PR / (P + R) | `vs_evaluate_detection` |
| 11 | Gyro zero-rate offset | Not removed (the proposal specifies none). Asked at Stage 5 and not answered | `vs_preprocess` |
| 12 | Demo uses the combined piezo + gyro rule for shots | Yes, so handling bumps become rejected shots; evaluation still reports both rules | `scripts/demo_synthetic.m` |

Not implemented, to keep to the proposal's scope:

- a rank correlation across release conditions ("if useful" in the proposal)
- a loose-mounting flag, which needs an operator entry in `meta.txt`; nothing in the
  signals identifies it
- a live display; the proposal allows offline file transfer, and the plots are written
  as PNG files

Still needed from real recordings before evaluation: `detect.noise_floor_threshold`,
`detect.swing_confirm_threshold_dps`, the actual sampling rates, the ringing duration
compared with the 150 ms refractory interval, the second-event ratio, and the
match tolerance (`evaluation.match_tolerance_s`).
