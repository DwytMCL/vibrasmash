# Settings change log

Every change to a setting in `config/default_config.m` after Stage 1 is recorded here:
date, setting, old value, new value, source of the evidence (for example a named pilot
recording), and reason. Settings are frozen before evaluation data is processed
(proposal, "Research design"); the freeze is recorded here as its own entry.

Changing a setting whose source is `proposal` changes the study described in the
proposal. Such a change must say so explicitly and be agreed before it is made.

| Date | Setting | Old | New | Evidence | Reason |
| --- | --- | --- | --- | --- | --- |
| 2026-10-21 | (all) | n/a | Initial values | `docs/settings_provenance.md` | Stage 1 baseline |
| 2026-10-21 | `preprocess.bias_method_continuous` (new) | n/a | `median_record` | Stage 4 design; no recordings yet | Continuous recordings have no pre-trigger segment, so the existing pre-trigger method cannot apply. Provisional. |
| 2026-10-21 | `detect.envelope_alignment` | `centered` | `trailing` | Stage 5 design and synthetic onset tests; no recordings yet | A centered window starts to include a burst half a window (2.5 ms) before the burst begins, so the threshold crossing and the start of the 100 ms RMS window would come early. A trailing window crosses just after the burst starts. Provisional. |
| 2026-10-21 | `spectrum.signal` (new) | n/a | `bias_removed` | Stage 6 design; no recordings yet | The proposal uses the spectrum to inspect noise and saturation artefacts; the 2 kHz digital low-pass would hide content up to the 3 kHz analog filter. Provisional. |
| 2026-10-21 | `spectrum.hann_form` (new) | n/a | `periodic` | Stage 6 design | The proposal says "Hann-windowed" without a form; periodic is the usual choice for spectral analysis. Provisional. |
| 2026-10-21 | `features.second_event_ratio` (new) | n/a | `2` | Stage 6 synthetic tests (seeds 1-10): without it, single-burst tails re-crossed the threshold inside the 100 ms window on 6 of 10 seeds | A re-crossing inside a feature window flags a second event only if the envelope then reaches 2 x the threshold within one envelope window. Must be checked on pilot recordings. Provisional. |
| 2026-10-21 | `consistency.block_key` (new) | n/a | `session` | Stage 7 design | One block = one session folder (one ten-shot run or volunteer block). Provisional. |
| 2026-10-21 | `config_version` | `stage1-2026-10-21` | `stage8-2026-10-21` | n/a | Records that settings were added after Stage 1. |
