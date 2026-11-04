function tests = test_features
%TEST_FEATURES Unit tests for the impact, swing and spectrum features
%   (src/features), the reference RMS and intensity index, and the session
%   role helpers. All signals are synthetic test inputs; nothing here is a
%   measurement.
tests = functiontests(localfunctions);
end

function setupOnce(~)
vs_setup();
end

% ---- Formulas -----------------------------------------------------------

function testRmsFormula(~)
n = (0:1999).';
x = 0.3 * sin(2 * pi * 10 * n / 2000);        % whole cycles
assert(abs(vs_impact_rms(x) - 0.3 / sqrt(2)) < 1e-12);
assert(abs(vs_impact_rms([3; 4]) - sqrt(12.5)) < 1e-12);
assert(isnan(vs_impact_rms([1; NaN])), 'A NaN must not be skipped');
assert(isnan(vs_impact_rms([])));
end

function testSpectrumReadsSineAmplitudeAtBinCentre(~)
fs = 19500;                                   % a measured rate, not nominal
k = 77;
n = (0:2047).';
x = 0.2 * sin(2 * pi * k * n / 2048) + 0.01;
s = vs_spectrum(x, fs, 'periodic');
assert(numel(s.freq_hz) == 1025 && numel(s.amp) == 1025);
assert(abs(s.df_hz - fs / 2048) < 1e-12);
assert(abs(s.freq_hz(k + 1) - k * fs / 2048) < 1e-9);
assert(abs(s.amp(k + 1) - 0.2) < 1e-9, 'Amplitude %g', s.amp(k + 1));
assert(abs(s.amp(1) - 0.01) < 1e-9, 'DC bin reads the offset');
assert(s.peak_hz == s.freq_hz(k + 1));
end

function testSpectrumRefusesNanAndOddLength(~)
expect_error(@() vs_spectrum([1; NaN; 2; 3], 100), 'vs_spectrum:nan');
expect_error(@() vs_spectrum(ones(5, 1), 100), 'vs_spectrum:length');
end

% ---- Features on synthetic fixtures -------------------------------------

function testFeaturesOfPlantedContacts(~)
[res, info, c] = process(struct('name', 'features')); %#ok<ASGLU>
s = res.shots;
assert(numel(s.shot) == 3, 'Expected 2 contacts and a frame tap');
assert(all(s.rms_valid) && all(s.fft_valid) && all(s.preimpact_valid));
% RMS of A*exp(-t/tau)*sin(2*pi*f*t) over T = 100 ms is close to
% A*sqrt(tau/(4T)) when f*T is large: 58.1 mV for the 300 mV contact,
% 48.4 mV for the 250 mV contact (15 ms decay).
ev = info.spec.events;
for e = 1:2
    expected = ev(e).piezo_amp_mv / 1000 * sqrt(ev(e).piezo_decay_s / (4 * 0.1));
    assert(abs(s.rms_v(e) / expected - 1) < 0.03, 'Shot %d RMS %g, expected %g', ...
        e, s.rms_v(e), expected);
    assert(abs(s.fft_peak_hz(e) - 750) <= res.spectra.freq_hz(2), 'Peak %g Hz', s.fft_peak_hz(e));
    assert(abs(s.preimpact_peak_dps(e) / ev(e).gyro_peak_dps - 1) < 0.05, ...
        'Swing peak %g', s.preimpact_peak_dps(e));
end
assert(s.preimpact_peak_dps(3) < 10, 'The frame tap has no swing');
assert(isequal(size(res.spectra.amp), [1025 3]));
end

function testBinsAndRmsLengthUseMeasuredRate(~)
spec.name = 'rate';
spec.piezo_fs_hz = 19800;                     % actual rate differs from nominal
[res, ~, c] = process(spec); %#ok<ASGLU>
fs = res.qc.piezo.measured_fs_hz;
assert(abs(fs - 19800) < 1);
assert(abs(res.spectra.freq_hz(2) - fs / 2048) < 1e-9);
assert(all(res.shots.rms_n_samples == round(0.1 * fs)));
end

function testIncompleteWindowsGiveNoValue(~)
spec.name = 'short';
spec.recording_mode = 'triggered';
spec.post_trigger_s = 0.090;                  % less than the 100 ms RMS window
[res, ~, c] = process(spec); %#ok<ASGLU>
s = res.shots;
assert(numel(s.shot) >= 2);
assert(all(isnan(s.rms_v)) && ~any(s.rms_valid), 'No RMS from a partial window');
assert(all(strcmp(s.rms_flags, 'rms_incomplete')));
assert(~any(s.fft_computed) && all(strcmp(s.fft_flags, 'fft_incomplete')), 'No zero-padding');
assert(all(isnan(res.spectra.amp(:))));
assert(all(s.preimpact_valid(1:2)), 'The swing window is unaffected');
end

function testGapInsideWindowIsFlaggedValueKept(~)
spec.name = 'gap';
spec.piezo_drop_s = [1.070 1.072];   % inside the first contact's windows, but
                                      % more than 50 ms after the onset: a gap
                                      % closer than that puts the onset in the
                                      % filter edge zone, where it is not counted
[res, ~, c] = process(spec); %#ok<ASGLU>
s = res.shots;
assert(~isempty(strfind(s.rms_flags{1}, 'rms_gap')) && ~s.rms_valid(1));
assert(~isnan(s.rms_v(1)), 'A complete but contaminated window still reports its value');
assert(~isempty(strfind(s.fft_flags{1}, 'fft_gap')) && ~s.fft_valid(1));
assert(s.rms_valid(2) && s.fft_valid(2), 'The second contact is clean');
end

function testClippingIsFlagged(~)
spec = make_synthetic_fixture();
spec.name = 'clip';
spec.events(1).piezo_amp_mv = 2500;           % beyond the 1650 mV headroom
[res, ~, c] = process(spec); %#ok<ASGLU>
s = res.shots;
assert(~isempty(strfind(s.rms_flags{1}, 'rms_clipped')) && ~s.rms_valid(1));
assert(~isempty(strfind(s.fft_flags{1}, 'fft_clipped')) && ~s.fft_valid(1));
assert(s.rms_valid(2));
end

function testSecondBurstInsideWindowIsFlagged(~)
spec = make_synthetic_fixture();
spec.name = 'second';
spec.events = spec.events(1:2);
spec.events(1).piezo_decay_s = 0.005;
spec.events(2).piezo_decay_s = 0.005;
spec.events(2).t_s = 1.060;                   % inside the refractory interval
[res, ~, c] = process(spec); %#ok<ASGLU>
s = res.shots;
assert(numel(s.shot) == 1, 'The refractory interval suppresses the second onset');
assert(~isempty(strfind(s.rms_flags{1}, 'rms_second_event')) && ~s.rms_valid(1));
assert(~isempty(strfind(s.fft_flags{1}, 'fft_second_event')));
end

function testRingingTailIsNotASecondEvent(~)
% The decaying tail of one burst hovers at the threshold and can cross it
% again; that must not be flagged (features.second_event_ratio).
for seed = 1:8
    spec.name = sprintf('tail%d', seed);
    spec.seed = seed;
    [res, ~, c] = process(spec); %#ok<ASGLU>
    assert(isempty(strfind(strjoin(res.shots.rms_flags.', ';'), 'second_event')), ...
        'Seed %d flagged a ringing tail', seed);
    clear c
end
end

function testRejectedDetectionsStayInTheTable(~)
spec = distractor_spec();
cfg = feature_cfg();
cfg.detect.swing_confirm_enabled = true;
[res, ~, c] = process(spec, cfg); %#ok<ASGLU>
s = res.shots;
assert(numel(s.shot) == 9, '6 contacts and 3 handling bumps are detected');
assert(sum(s.accepted) == 6);
assert(all(strcmp(s.status(~s.accepted), 'rejected_not_swing_confirmed')));
assert(~any(s.rms_valid(~s.accepted)) && all(~isnan(s.rms_v(~s.accepted))), ...
    'Rejected shots keep their values but are never valid');
end

function testShortPreTriggerMakesSwingWindowIncomplete(~)
spec.name = 'shortpre';
spec.recording_mode = 'triggered';
spec.pre_trigger_s = 0.200;                   % less than the 250 ms swing window
[res, ~, c] = process(spec); %#ok<ASGLU>
s = res.shots;
assert(all(~cellfun(@isempty, strfind(s.preimpact_flags, 'preimpact_incomplete'))));
assert(~any(s.preimpact_valid));
assert(all(s.rms_valid), 'The RMS window is unaffected');
end

% ---- Reference and index ------------------------------------------------

function testReferenceIsMedianOfValidShotsAndIndexIs100There(~)
rms = [0.10 0.12 0.08 0.11 0.09 0.10 0.13 0.10 0.12 0.11 5.0].';
valid = [true(10, 1); false];                 % an invalid shot must not count
r = fake_result('ref1', 'reference', 'middle', rms, valid);
cfg = default_config();
ref = vs_reference_rms({r}, cfg);
assert(ref.rms_ref_v == median(rms(1:10)) && ref.n_valid == 10 && strcmp(ref.status, 'ok'));
assert(ref.n_attempted == 11);
s = fake_result('stroke1', 'stroke', '', [ref.rms_ref_v; 0.2; 0.3], [true; true; false]);
shots = vs_intensity_index(s.shots, s.meta, ref, cfg);
assert(abs(shots.intensity_index(1) - 100) < 1e-12);
assert(abs(shots.intensity_index(2) - 100 * 0.2 / ref.rms_ref_v) < 1e-12);
assert(shots.intensity_index(2) > 100, 'Values may exceed 100');
assert(isnan(shots.intensity_index(3)) && strcmp(shots.index_note{3}, 'rms_not_valid'));
end

function testReferenceCombinesSessionsAndReportsShortfall(~)
cfg = default_config();
a = fake_result('refA', 'reference', 'middle', [0.1; 0.2; 0.3; 0.4], true(4, 1));
b = fake_result('refB', 'reference', 'middle', [0.5; 0.6; 0.7], true(3, 1));
ref = vs_reference_rms({a, b}, cfg);
assert(ref.n_valid == 7 && ref.rms_ref_v == 0.4 && strcmp(ref.status, 'shortfall'));
assert(~isempty(strfind(ref.note, '7 valid')));
s = fake_result('stroke1', 'stroke', '', 0.4, true);
shots = vs_intensity_index(s.shots, s.meta, ref, cfg);
assert(shots.intensity_index == 100, 'A shortfall is reported, not hidden');
assert(strcmp(shots.index_note{1}, 'reference_shortfall_7_of_10'));
end

function testReferenceRules(~)
cfg = default_config();
expect_error(@() vs_reference_rms({fake_result('x', 'stroke', 'middle', 0.1, true)}, cfg), ...
    'vs_reference_rms:notReference');
expect_error(@() vs_reference_rms({fake_result('x', 'reference', 'high', 0.1, true)}, cfg), ...
    'vs_reference_rms:condition');
a = fake_result('refA', 'reference', 'middle', 0.1, true);
b = fake_result('refB', 'reference', 'middle', 0.1, true);
b.meta.afe_gain = '20';
expect_error(@() vs_reference_rms({a, b}, cfg), 'vs_reference_rms:setupMismatch');
end

function testIndexRefusesAnotherSetupAndNeedsAReference(~)
cfg = default_config();
ref = vs_reference_rms({fake_result('refA', 'reference', 'middle', 0.1, true)}, cfg);
s = fake_result('stroke1', 'stroke', '', 0.1, true);
shots = vs_intensity_index(s.shots, s.meta, [], cfg);
assert(isnan(shots.intensity_index) && strcmp(shots.index_note{1}, 'no_reference'));
s.meta.mount_id = 'other';
expect_error(@() vs_intensity_index(s.shots, s.meta, ref, cfg), ...
    'vs_intensity_index:setupMismatch');
end

function testSyntheticReferenceSessionEndToEnd(~)
spec = make_synthetic_fixture();
spec.name = 'reference';
spec.synthetic_role = 'reference';
spec.meta_extra = struct('condition', 'middle');
spec.duration_s = 5.5;
amps = [200 210 190 205 195 200 215 185 200 210];
ev = spec.events(1);
for e = 1:10
    ev.t_s = 0.5 * e;
    ev.piezo_amp_mv = amps(e);
    ev.gyro_peak_dps = 0;                     % stationary rig: no swing
    spec.events(e) = ev;
end
cfg = feature_cfg();
cfg.detect.swing_confirm_enabled = true;     % must be bypassed for reference sessions
[res, ~, c] = process(spec, cfg); %#ok<ASGLU>
assert(strcmp(res.role, 'reference') && res.synthetic);
assert(strcmp(res.meta.session_type, 'synthetic'), 'Still labelled synthetic');
assert(~res.det.swing_rule_applied && all(res.shots.accepted));
ref = vs_reference_rms({res}, cfg);
assert(ref.n_valid == 10 && strcmp(ref.status, 'ok') && ref.synthetic);
assert(ref.rms_ref_v == median(res.shots.rms_v));
assert(~isempty(strfind(ref.note, 'SYNTHETIC')));
end

function testSessionRole(~)
meta = struct('session_type', 'synthetic', 'synthetic', 'true', 'synthetic_role', 'stroke');
assert(strcmp(vs_session_role(meta), 'stroke'));
meta.synthetic = 'false';                     % a real recording ignores the key
assert(strcmp(vs_session_role(meta), 'synthetic'));
meta = struct('session_type', 'controlled');
assert(strcmp(vs_session_role(meta), 'controlled'));
end

function testGeneratorKeepsSyntheticLabels(~)
spec.name = 'labels';
spec.meta_extra = struct('session_type', 'stroke');
expect_error(@() generate(spec), 'make_synthetic_fixture:metaExtra');
spec.meta_extra = struct('condition', 'low', 'block', 2);
spec.synthetic_role = 'controlled';
[info, c] = generate(spec); %#ok<ASGLU>
meta = vs_read_meta(fullfile(info.folder, 'meta.txt'));
assert(strcmp(meta.session_type, 'synthetic') && strcmp(meta.split, 'test'));
assert(strcmp(meta.synthetic_role, 'controlled') && strcmp(meta.condition, 'low'));
assert(strcmp(meta.block, '2'));
end

% ---- Helpers ------------------------------------------------------------

function cfg = feature_cfg()
% Test values for the two pilot settings, chosen for the synthetic fixture
% (2 mV noise), not measured; they must not be copied into the config.
cfg = default_config();
cfg.detect.noise_floor_threshold = 0.005;
cfg.detect.swing_confirm_threshold_dps = 60;
end

function [res, info, cleanup] = process(spec, cfg)
if nargin < 2
    cfg = feature_cfg();
end
[info, cleanup] = generate(spec);
res = vs_process_session(info.folder, cfg);
end

function [info, cleanup] = generate(spec)
spec.out_dir = tempname();
mkdir(spec.out_dir);
cleanup = onCleanup(@() rmdir(spec.out_dir, 's'));
info = make_synthetic_fixture(spec);
end

function r = fake_result(sid, role, condition, rms, valid)
% A minimal session result for reference and index tests (no signals).
r.folder = '';
r.synthetic = false;
r.meta = struct('session_id', sid, 'session_type', role, 'afe_gain', '10', ...
    'mount_id', 'shaft-A', 'racket_id', 'R1');
if ~isempty(condition)
    r.meta.condition = condition;
end
n = numel(rms);
r.shots.session_id = repmat({sid}, n, 1);
r.shots.shot = (1:n).';
r.shots.rms_v = rms(:);
r.shots.rms_valid = valid(:);
end

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

function expect_error(fn, id)
try
    fn();
catch err
    assert(strcmp(err.identifier, id), 'Expected %s, got %s: %s', id, err.identifier, err.message);
    return
end
error('test:noError', 'Expected error %s, but none was raised', id);
end
