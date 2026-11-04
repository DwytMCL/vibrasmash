# Installing and checking the environment (MATLAB)

Status, 2026-10-21: `smoke_test` passes 8 / 8 checks and `run_tests` passes 8 / 8 in MATLAB R2026b on Windows with the
Signal Processing Toolbox installed (`docs/stage1_test_record.txt`). Older MATLAB
releases down to R2019b are expected to work but have not been tried.

## Requirements

| Requirement | Why | Notes |
| --- | --- | --- |
| MATLAB R2019b or newer | `matlab -batch`, `isfolder`, unit test framework | Older releases may work but are not supported |
| Signal Processing Toolbox | `butter`, `filtfilt`, `hann` | The only toolbox needed |

No other toolboxes (no Statistics, no DSP System Toolbox). GNU Octave 8.4 with the
`signal` package also runs the setup, smoke test and environment check, but the
test runner needs MATLAB.

## Check what you have

In the MATLAB Command Window:

```
ver                                   % lists MATLAB release and every installed toolbox
ver('signal')                         % Signal Processing Toolbox only (empty = not installed)
license('test', 'Signal_Toolbox')     % 1 = licensed and usable, 0 = not
```

If the Signal Processing Toolbox is missing: on a university licence it is usually
available at no cost. Install it from MATLAB with **Home > Add-Ons > Get Add-Ons**,
search "Signal Processing Toolbox", or re-run the MathWorks installer and tick it.
If you cannot get it, say so before Stage 4; the two filter functions can be written
from scratch, but that adds work and its own tests.

## Get the files

1. Download `vibrasmash_stage1.zip` from the project.
2. Extract it to a folder without spaces, for example `C:\work\vibrasmash`.
   (You should then have `C:\work\vibrasmash\run_tests.m`.)

## 1. Smoke test (run first)

In MATLAB:

```
cd C:\work\vibrasmash
addpath scripts
smoke_test
```

It checks the MATLAB version, the Signal Processing Toolbox (installed and
licensed), that the required functions exist, runs `butter` + `filtfilt` and a Hann
FFT on tiny synthetic sines, does a CSV round trip in a temporary folder, and saves
a figure to PNG without opening a window. It ends with `Smoke test PASSED` or lists
each failed check.

## 2. Test suite

```
cd C:\work\vibrasmash
run_tests
```

Expected at Stage 1: `Total: 8 / 8 tests passed`.

From Command Prompt or PowerShell instead (exit code 0 = all passed):

```
matlab -batch "cd('C:/work/vibrasmash'); assert(run_tests())"
```

`run_tests` uses MATLAB's built-in unit test framework
(`matlab.unittest.TestSuite.fromFolder`) on everything under `tests/`, then prints
one line per test and a total.

## What to send back

Copy the full Command Window output of `smoke_test` and `run_tests` into the
project chat, and the output of `ver` (or just the MATLAB release and whether the
Signal Processing Toolbox is listed).

## Seeing the outputs (synthetic demo)

```matlab
vs_setup; demo_synthetic
```

This writes a folder `results/synthetic_<date>_<time>_demo/` with CSV files, plots and a
run log, made from labelled synthetic sessions. It shows what a real run produces. None
of its numbers is a measurement.
