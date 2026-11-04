# VibraSmash Phone Recorder

A small web app that records the **phone's accelerometer** to CSV, for the VibraSmash
project.

> **This is phone accelerometer data, not ESP32 piezo/IMU data.** It does not validate
> the VibraSmash hardware. Its files are not in the ESP32 format in the VibraSmash
> repo's `docs/data_format.md`, and the MATLAB pipeline does not read them.
>
> The sample rate is whatever the browser delivers, often 50–100 Hz on Android Chrome
> and sometimes uneven. That is far below the proposal's 20 kHz piezo rate and its
> 200 Hz IMU rate. The measured rate is written to each `_meta.txt`; check it rather
> than assuming it.

## Android app (APK)

`android/VibraSmashRecorder.apk` (built by `android/build_apk.sh`; the APK itself is not committed) is a real Android app with the same page inside. It
needs no server and no internet, and keeps the screen on while open. Files are saved to
**Download/VibraSmash/**.

- Install: open the APK from a file manager, or in Termux run
  `termux-open phone-recorder/android/VibraSmashRecorder.apk`, then tap
  Install. Android may first ask you to allow installs from that app.
- **Share:** after Stop, tap **Share last recording**. Android's share menu opens with
  `<session>_accel.csv` and `<session>_meta.txt` attached and a one-line description,
  so you can send them with Messenger, Gmail, Drive and so on. The share copies are
  private to the app and are replaced at the next Start. The Download/VibraSmash copies
  stay. In the Chrome version the same button uses the browser's share menu, when Chrome
  supports sharing files.
- Rebuild after editing `index.html`: `sh phone-recorder/android/build_apk.sh`.
  Raise `VERSION_CODE` (e.g. `VERSION_CODE=2 sh android/build_apk.sh`) so it installs
  over the old version.
- `android/vibrasmash.keystore` is the signing key. Keep it: an update signed with a
  different key won't install over the old app. It is a personal key, not for the Play
  Store.
- To give the app to someone else, send them the APK file. They have to allow installing
  from unknown sources, and Play Protect may warn them because it's not from the Play
  Store.

## Web version (optional)

The same page also runs in Chrome from a local server, as described below.

## Start the server

In Termux:

```sh
phone-recorder/start.sh
```

This serves the folder at `http://localhost:8080`, using `python -m http.server` if
Python is installed (`pkg install python`) and `node serve.js` otherwise. It listens on
127.0.0.1 only, so other devices can't reach it. Leave Termux running, and stop the
server with Ctrl+C.

## Open it

Open **http://localhost:8080** in Chrome on the same phone. `localhost` counts as a
secure context, so motion sensors are allowed. From any other address (for example the
phone's LAN IP) the page needs **HTTPS**, or the browser blocks motion events.

## Install to the home screen

With the page open in Chrome: ⋮ menu → **Add to Home screen** (or **Install app**) →
Install. The icon opens the app full screen.

The app is a page served from Termux, so **start the server first** each time before
tapping the icon. The service worker caches the page so it may open without the server,
but don't rely on that.

## Record

1. Type a session name, e.g. `2026-11-05_phone_01`. Only letters, digits, `_` and `-`
   are kept. A blank name becomes `phone_<date>_<time>`.
2. Tap **Start**. On iPhone, allow motion access when asked.
3. Keep the screen on and the app in front. Browsers pause motion events when the page
   is hidden. The app asks for a screen wake lock and warns you if the page was hidden.
4. Tap **Stop**. Two files go to Downloads:
   - `<session>_accel.csv` has the header `t_us,ax,ay,az` and one row per real motion
     event. Acceleration is in m/s² with 6 decimal places. `t_us` is integer
     microseconds since Start.
   - `<session>_meta.txt` has `key=value` lines: sensor, source, session_id,
     device_model, user_agent, start_time_iso, n_samples, duration_s,
     measured_rate_hz = (n−1)/duration, median_dt_ms, max_gap_ms, accel_source, units.
     It also has `n_events_without_data`, the number of events that carried no
     acceleration and were skipped.

   The first time, Chrome may ask to allow the site to **download multiple files**.
   Allow it, or the meta file is blocked.

## Live DSP demo

While recording, the app runs the same three steps as the VibraSmash pipeline, scaled
down to the phone's sample rate, and plots the last 5 seconds:

1. **High-pass filter** (first order, 1 Hz) on each axis. It removes gravity and slow
   tilting. The filter uses each sample's real time step, so uneven timing is handled
   without resampling.
2. **Moving RMS envelope** over 100 ms of the filtered magnitude.
3. **Threshold detection.** A bump is counted when the envelope crosses the threshold
   (adjustable with the slider, default 2 m/s²). The detector re-arms once the envelope
   drops below half the threshold, and needs at least 300 ms between bumps. The first
   1 s after Start is ignored while the filter settles.

The demo settings and detected bump times are added to `_meta.txt` as `demo_*` keys.
The CSV holds only the raw samples.

**What this demo is and isn't.** VibraSmash runs these steps on a 20 kHz piezo signal
(80 Hz–2 kHz band, 5 ms RMS window). The phone gives about 50–100 Hz. The demo settings
are chosen to make the steps visible at that rate. They are not the pipeline's settings
and weren't tuned on any data. A short, sharp impact can fall between two phone samples
and be missed (`test/dsp.test.js` shows this with a synthetic 20 ms impact), which is
exactly why VibraSmash samples at 20 kHz. That makes a useful point to show your
professor.

**Demo script:** hold the phone still → the envelope sits near zero. Tilt it slowly →
still no bump, because the high-pass filter removes it. Tap the phone or knock the table
it's on → the envelope spikes, crosses the threshold and the count goes up. Raise the
threshold → weaker taps are no longer counted.

## What the data is

- Values are `accelerationIncludingGravity`, or `acceleration` (gravity removed) when
  the first is unavailable. `accel_source` says which, or `mixed`.
- Time comes from each event's `timeStamp`, falling back to `performance.now()` when
  that is missing. Nothing is resampled, interpolated or filled. Gaps stay as gaps and
  show in `max_gap_ms`.
- Events stamped before Start are not recorded. Events without acceleration values are
  counted in `n_events_without_data` and not written.
- Axes follow the device frame defined in the W3C spec (x right, y up, z out of the
  screen). Browsers differ in sign conventions, so note your phone's orientation when
  you record.

## Files

| File | Purpose |
| --- | --- |
| `index.html` | The whole app. The CSV/meta logic sits between `BEGIN CORE` / `END CORE` |
| `manifest.json`, `sw.js`, `icon-*.png` | Home-screen install |
| `start.sh`, `serve.js` | Start the local server (`serve.js` is the no-Python fallback) |
| `test/core.test.js` | `node test/core.test.js`: tests the CSV/meta logic with **synthetic** fake events |
| `test/dsp.test.js` | `node test/dsp.test.js`: tests the DSP demo with **synthetic** signals |
| `tools/make_icons.js` | Regenerates the icons |
