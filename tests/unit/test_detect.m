function tests = test_detect
%TEST_DETECT Unit tests for impact detection (src/detect) and the gyro
%   helpers it uses (vs_angular_speed, vs_preimpact_peak).
%   All signals are synthetic test inputs; nothing here is a measurement.
tests = functiontests(localfunctions);
end

function setupOnce(~)
vs_setup();
end

% ---- Moving RMS envelope -------------------------------------------------

function testMovingRmsOfConstantMagnitudeIsThatMagnitude(~)
x = 0.5 * (-1).^(1:200).';
env = vs_moving_rms(x, 10, 'trailing');
assert(max(abs(env - 0.5)) < 1e-12);
end

function testTrailingWindowUsesOnlyPastSamples(~)
x = zeros(100, 1); x(50) = 1;
env = vs_moving_rms(x, 10, 'trailing');
assert(all(env(1:49) == 0) && all(env(60:end) == 0));
assert(max(abs(env(50:59) - sqrt(1/10))) < 1e-12);
end

function testCenteredWindowAlignment(~)
x = zeros(100, 1); x(50) = 1;
env = vs_moving_rms(x, 10, 'centered');
assert(isequal(find(env > 0).', 46:55));
end

function testEnvelopeStaysInsideSegments(~)
x = zeros(100, 1); x(50) = 1;
env = vs_moving_rms(x, 10, 'trailing', [1 50; 51 90]);
assert(all(env(51:90) == 0), 'Nothing may cross a segment boundary');
assert(all(isnan(env(91:100))), 'Samples outside every segment are NaN');
assert(abs(env(50) - sqrt(1/10)) < 1e-12);
end

% ---- Threshold -----------------------------------------------------------

function testThresholdIsMedianPlusSixMad(~)
[thr, s] = vs_adaptive_threshold([1 2 3 4 100].', 6, 0);
assert(s.median == 3 && s.mad == 1 && thr == 9 && strcmp(s.limited_by, 'statistical'));
end

function testNoiseFloorLimitsThreshold(~)
[thr, s] = vs_adaptive_threshold([1 2 3 4 100].', 6, 20);
assert(thr == 20 && strcmp(s.limited_by, 'noise_floor'));
end

function testNoiseFloorIsRequired(~)
expect_error(@() vs_adaptive_threshold([1 2 3].', 6, []), 'vs_adaptive_threshold:noiseFloor');
end

% ---- Detection on synthetic fixtures ------------------------------------

function testDetectionRefusesWithoutNoiseFloor(~)
[info, c] = generate(struct('name', 'nofloor')); %#ok<ASGLU>
cfg = default_config();                      % noise floor is a pilot value, unset
rec = vs_read_recording(info.folder);
qc = vs_validate_recording(rec, cfg);
pre = vs_preprocess(rec, qc, cfg);
expect_error(@() vs_detect_impacts(rec, qc, pre, cfg), 'vs_detect_impacts:noiseFloor');
end

function testDetectsPlantedBurstsNearTheirOnsets(~)
[det, info, c] = detect(struct('name', 'onsets')); %#ok<ASGLU>
% Default events: contact, contact, dry swing (no burst), frame tap.
expected = info.event_onset_us([1 2 4]);
assert(numel(det.onset_t_us) == 3, 'Found %d detections', numel(det.onset_t_us));
err_ms = (det.onset_t_us - expected) / 1000;
% Zero-phase high-pass filtering spreads a sharp burst start backwards in
% time, so the envelope crosses up to about 2 ms early for large bursts.
assert(all(err_ms >= -3 & err_ms <= 1), 'Onset errors (ms): %s', mat2str(err_ms.', 3));
end

function testNoiseOnlyGivesNoDetections(~)
spec = make_synthetic_fixture();
spec.name = 'noise';
[spec.events.piezo_amp_mv] = deal(0);
[det, ~, c] = detect(spec); %#ok<ASGLU>
assert(isempty(det.onset_t_us));
end

function testRefractoryCountsBurstsWithin150msOnce(~)
spec = make_synthetic_fixture();
spec.name = 'refractory';
spec.events = spec.events(1:2);
% Short decays, so the second burst has died away (about exp(-10) of its
% amplitude) by the time the 150 ms refractory from the first onset ends.
% With the default 15 ms decay it could still be near threshold then and
% re-cross, depending on the noise (seen in MATLAB, not in Octave).
spec.events(1).piezo_decay_s = 0.005;
spec.events(2).piezo_decay_s = 0.005;
spec.events(2).t_s = 1.100;                 % 100 ms after the first
[det, ~, c] = detect(spec); %#ok<ASGLU>
assert(numel(det.onset_t_us) == 1);
spec.name = 'refractory2';
spec.events(2).t_s = 1.200;                 % 200 ms after the first
[det, ~, c2] = detect(spec); %#ok<ASGLU>
assert(numel(det.onset_t_us) == 2);
end

function testRingingWithinRefractoryIsCountedOnce(~)
% A 30 ms decay keeps this burst above threshold for about 110 ms, with
% envelope ripple; the 150 ms refractory interval counts it once.
spec = make_synthetic_fixture();
spec.name = 'ringing';
spec.events = spec.events(1);
spec.events(1).piezo_decay_s = 0.030;
[det, ~, c] = detect(spec); %#ok<ASGLU>
assert(numel(det.onset_t_us) == 1);
end

function testRingingLongerThanRefractoryIsCountedAgain(~)
% Documents a limitation of the proposal's rule rather than a wish: a burst
% still above threshold more than 150 ms after its onset can cross again
% and be counted a second time. Real ringing durations must be checked in
% pilot recordings.
spec = make_synthetic_fixture();
spec.name = 'longring';
spec.events = spec.events(1);
spec.events(1).piezo_decay_s = 0.100;
[det, ~, c] = detect(spec); %#ok<ASGLU>
assert(numel(det.onset_t_us) == 2);
assert(diff(det.onset_t_us) >= 150000);
end

function testDistractorsPiezoOnlyVersusSwingConfirmed(~)
% Our own seeded fixture, in the spirit of the distractors in the earlier
% prototype: 6 contacts with swings, 3 handling bumps (240 Hz, no swing),
% 2 dry swings (no burst) and 2 bumps below the noise floor.
spec = distractor_spec();
[det, info, c] = detect(spec); %#ok<ASGLU>
cat = {spec.events.category};
amp = [spec.events.piezo_amp_mv];
contacts = info.event_onset_us(strcmp(cat, 'contact'));
handling = info.event_onset_us(strcmp(cat, 'handling') & amp > 10);
% Piezo-only: every burst above threshold is detected, including handling.
assert(isequal(match(det.onset_t_us, [contacts; handling]), true(9, 1)));
assert(numel(det.onset_t_us) == 9, 'Piezo-only found %d', numel(det.onset_t_us));
% Combined rule: only the bursts preceded by a swing are confirmed.
confirmed = det.onset_t_us(det.swing_confirmed);
assert(numel(confirmed) == 6 && all(match(confirmed, contacts)));
end

function testSwingRuleIsNotAppliedToStationaryTests(~)
[info, c] = generate(struct('name', 'stationary')); %#ok<ASGLU>
txt = strrep(fileread(info.files.meta), 'session_type = synthetic', 'session_type = reference');
write_text(info.files.meta, txt);
cfg = detect_cfg();
cfg.detect.swing_confirm_enabled = true;
det = run_detection(info.folder, cfg);
assert(~det.swing_rule_applied && all(det.accepted));
end

function testSwingRuleAppliedWhenEnabled(~)
cfg = detect_cfg();
cfg.detect.swing_confirm_enabled = true;
[info, c] = generate(struct('name', 'swingrule')); %#ok<ASGLU>
det = run_detection(info.folder, cfg);
assert(det.swing_rule_applied);
assert(isequal(det.accepted, det.swing_confirmed));
assert(sum(det.accepted) == 2, 'Only the two contacts have swings');
end

function testSwingRuleEnabledWithoutThresholdIsAnError(~)
cfg = detect_cfg();
cfg.detect.swing_confirm_enabled = true;
cfg.detect.swing_confirm_threshold_dps = [];
[info, c] = generate(struct('name', 'noswingthr')); %#ok<ASGLU>
expect_error(@() run_detection(info.folder, cfg), 'vs_confirm_swing:threshold');
end

function testTriggeredRecordsGetTheirOwnThresholds(~)
[det, ~, c] = detect(struct('name', 'trig', 'recording_mode', 'triggered')); %#ok<ASGLU>
assert(numel(det.thresholds) == 3);
assert(isequal(det.record_id.', [1 2 3]));
end

function testCrossingInFilterEdgeZoneIsListedNotCounted(~)
spec = make_synthetic_fixture();
spec.name = 'edge';
spec.events = spec.events(1);
spec.events(1).t_s = 0.020;                 % inside the 50 ms edge zone
spec.events(1).gyro_peak_dps = 0;
[det, info, c] = detect(spec); %#ok<ASGLU>
assert(isempty(det.onset_t_us));
assert(numel(det.edge_candidates.t_us) >= 1);
assert(abs(det.edge_candidates.t_us(1) - info.event_onset_us(1)) < 5000);
end

% ---- Gyro helpers -------------------------------------------------------

function testAngularSpeedIsVectorMagnitude(~)
assert(isequal(vs_angular_speed([3 4 12; 0 0 0]), [13; 0]));
end

function testPreimpactPeakUsesTheWindowBeforeOnset(~)
t = (0:5000:2000000).';
w = zeros(size(t));
w(t == 700000) = 100;                      % one marked sample
p = vs_preimpact_peak(t, w, 800000, 0.25, 200);
assert(p.peak_dps == 100 && p.peak_t_us == 700000 && p.complete && p.n_samples == 50);
p = vs_preimpact_peak(t, w, 960000, 0.25, 200);   % window starts at 710000
assert(p.peak_dps == 0);
p = vs_preimpact_peak(t, w, 700000, 0.25, 200);   % the onset sample itself is excluded
assert(p.peak_dps == 0);
p = vs_preimpact_peak(t, w, 100000, 0.25, 200);   % data starts inside the window
assert(~p.complete);
invalid = false(size(t)); invalid(t == 700000) = true;
p = vs_preimpact_peak(t, w, 800000, 0.25, 200, invalid);
assert(p.touches_invalid);
end

% ---- Helpers ------------------------------------------------------------

function spec = distractor_spec()
spec = make_synthetic_fixture();
spec.name = 'distractors';
spec.seed = 7;
spec.duration_s = 7.5;
cats = {'contact', 'handling', 'contact', 'dry_swing', 'contact', 'handling', 'contact', ...
        'handling', 'contact', 'dry_swing', 'handling', 'contact', 'handling'};
amps = [300 40 220 0 260 40 180 40 240 0 2 200 2];
swing = [150 0 120 140 135 0 110 0 145 130 0 125 0];
freq = [750 240 750 750 750 240 750 240 750 750 240 750 240];
for e = 1:numel(cats)
    ev(e).category = cats{e}; %#ok<AGROW>
    ev(e).t_s = 0.5 * e;
    ev(e).piezo_amp_mv = amps(e);
    ev(e).piezo_freq_hz = freq(e);
    ev(e).piezo_decay_s = 0.015;
    ev(e).gyro_peak_dps = swing(e);
    ev(e).gyro_lead_s = 0.060;
    ev(e).gyro_width_s = 0.040;
end
spec.events = ev;
end

function tf = match(found_us, expected_us)
% For each expected onset, true if a detection lies within 3 ms of it.
tf = false(numel(expected_us), 1);
for i = 1:numel(expected_us)
    tf(i) = any(abs(found_us - expected_us(i)) <= 3000);
end
end

function cfg = detect_cfg()
% Test values for the two pilot settings. They are chosen for the synthetic
% fixture (2 mV noise), not measured, and must not be copied into the config.
cfg = default_config();
cfg.detect.noise_floor_threshold = 0.005;      % volts
cfg.detect.swing_confirm_threshold_dps = 60;
end

function det = run_detection(folder, cfg)
rec = vs_read_recording(folder);
qc = vs_validate_recording(rec, cfg);
pre = vs_preprocess(rec, qc, cfg);
det = vs_detect_impacts(rec, qc, pre, cfg);
end

function [det, info, cleanup] = detect(spec)
[info, cleanup] = generate(spec);
det = run_detection(info.folder, detect_cfg());
end

function [info, cleanup] = generate(spec)
spec.out_dir = tempname();
mkdir(spec.out_dir);
cleanup = onCleanup(@() rmdir(spec.out_dir, 's'));
info = make_synthetic_fixture(spec);
end

function expect_error(fn, id)
try
    fn();
catch err
    assert(strcmp(err.identifier, id), 'Expected %s, got %s: %s', id, err.identifier, err.message);
    return
end
error('test:noError', 'Expected error %s, but none was raised', id);
end

function write_text(file, txt)
fid = fopen(file, 'w');
fwrite(fid, txt);
fclose(fid);
end
