function tests = test_analysis
%TEST_ANALYSIS Unit tests for block consistency (CV) and detection
%   evaluation (src/analysis). Inputs are hand-made tables or synthetic
%   fixtures; nothing here is a measurement.
tests = functiontests(localfunctions);
end

function setupOnce(~)
vs_setup();
end

% ---- CV ------------------------------------------------------------------

function testCvFormula(~)
[cv, m, sd] = vs_cv([1 2 3]);
assert(m == 2 && sd == 1 && cv == 50, 'Sample (n - 1) standard deviation');
x = [0.10 0.12 0.08 0.11 0.09 0.10 0.13 0.10 0.12 0.11];
assert(abs(vs_cv(x) - 100 * std(x) / mean(x)) < 1e-12);
assert(isnan(vs_cv(5)) && isnan(vs_cv([])));
assert(isnan(vs_cv([0 0])), 'A non-positive mean gives no CV');
expect_error(@() vs_cv([1 NaN 3]), 'vs_cv:nan');
end

% ---- Consistency ---------------------------------------------------------

function testBlockCvsUseEachFeaturesValidShots(~)
cfg = default_config();
rms = (0.10:0.01:0.19).';
swing = (100:10:190).';
r = fake_shots('P01_b1', 'stroke', rms, swing);
r.shots.rms_valid(3) = false;                 % RMS window contaminated
r.shots.rms_flags{3} = 'rms_gap';
r.shots.preimpact_valid([1 2]) = false;       % swing window incomplete
r.shots.preimpact_flags([1 2]) = {'preimpact_incomplete'};
b = vs_consistency({r}, cfg);
keep = true(10, 1); keep(3) = false;
assert(b.rms_n_valid == 9 && abs(b.rms_cv_pct - 100 * std(rms(keep)) / mean(rms(keep))) < 1e-9);
assert(b.swing_n_valid == 8 && abs(b.swing_cv_pct - 100 * std(swing(3:10)) / mean(swing(3:10))) < 1e-9);
assert(strcmp(b.rms_status{1}, 'sufficient') && strcmp(b.swing_status{1}, 'sufficient'));
assert(strcmp(b.rms_invalid_reasons{1}, 'rms_gap:1'));
assert(strcmp(b.swing_invalid_reasons{1}, 'preimpact_incomplete:2'));
assert(strcmp(b.participant{1}, 'P01') && strcmp(b.block_no{1}, '1'));
end

function testFewerThanEightValidShotsIsInsufficientButReported(~)
cfg = default_config();
r = fake_shots('P01_b2', 'stroke', (0.1:0.01:0.19).', (100:10:190).');
r.shots.accepted(1:3) = false;
r.shots.status(1:3) = {'rejected_not_swing_confirmed'};
r.shots.rms_valid(1:3) = false;
r.shots.preimpact_valid(1:3) = false;
b = vs_consistency({r}, cfg);
assert(b.n_detected == 10 && b.n_accepted == 7 && b.n_rejected == 3);
assert(strcmp(b.rejected_reasons{1}, 'rejected_not_swing_confirmed:3'));
assert(strcmp(b.rms_status{1}, 'insufficient') && ~isnan(b.rms_cv_pct), ...
    'An insufficient block still has its CV calculated and labelled');
assert(isempty(b.rms_invalid_reasons{1}), 'Rejected detections are counted as rejected, not invalid');
end

function testStationaryBlocksHaveNoSwingCvAndMiddleTargetIsReported(~)
cfg = default_config();
r = fake_shots('ctrl_mid_run1', 'controlled', 0.1 * ones(10, 1) + (0:9).' * 1e-3, ones(10, 1));
r.meta.condition = 'middle';
b = vs_consistency({r}, cfg);
assert(strcmp(b.swing_status{1}, 'stationary_session') && isnan(b.swing_cv_pct));
assert(b.rms_cv_pct < 15 && strcmp(b.target_note{1}, 'middle_rms_cv_at_or_below_15_pct_target'));
r.shots.rms_v = [0.05 0.15 0.05 0.15 0.05 0.15 0.05 0.15 0.05 0.15].';
b = vs_consistency({r}, cfg);
assert(strcmp(b.target_note{1}, 'middle_rms_cv_above_15_pct_target'));
end

% ---- Annotations ---------------------------------------------------------

function testReadsAnnotationsInAnyColumnOrderWithCrlf(~)
f = write_tmp(['session,action_id,category,t_start_s,t_end_s,split' char([13 10]) ...
    'S1,1,contact,1.0,1.2,evaluation' char([13 10]) 'S1,2,dry_swing,2.0,2.2,evaluation' char([13 10])]);
c = onCleanup(@() delete(f));
ann = vs_read_annotations(f);
assert(isequal(ann.action_id, [1; 2]) && isequal(ann.category, {'contact'; 'dry_swing'}));
assert(isequal(ann.t_end_s, [1.2; 2.2]) && strcmp(ann.split{2}, 'evaluation'));
end

function testAnnotationErrors(~)
h = 'action_id,category,t_start_s,t_end_s,session,split\n';
cases = {
    [h '1,contact,1.0,1.2,S1,evaluation\n2,contact,1.1,1.3,S1,evaluation\n'], 'vs_read_annotations:overlap'
    [h '1,smash,1.0,1.2,S1,evaluation\n'], 'vs_read_annotations:category'
    [h '1,contact,1.2,1.0,S1,evaluation\n'], 'vs_read_annotations:interval'
    [h '1,contact,1.0,1.2,S1,evaluation\n1,contact,2.0,2.2,S1,evaluation\n'], 'vs_read_annotations:duplicateId'
    'action_id,category,t_start_s,session,split\n1,contact,1.0,S1,evaluation\n', 'vs_read_annotations:missingColumn'
    [h '1,contact,abc,1.2,S1,evaluation\n'], 'vs_read_annotations:number'
    };
for i = 1:size(cases, 1)
    f = write_tmp(sprintf(cases{i, 1}));
    expect_error(@() vs_read_annotations(f), cases{i, 2});
    delete(f);
end
% The same action ids in two sessions are fine, and files concatenate.
f1 = write_tmp(sprintf([h '1,contact,1.0,1.2,S1,evaluation\n']));
f2 = write_tmp(sprintf([h '1,contact,1.0,1.2,S2,evaluation\n']));
ann = vs_read_annotations({f1, f2});
assert(numel(ann.action_id) == 2 && isequal(ann.session, {'S1'; 'S2'}));
delete(f1); delete(f2);
end

% ---- Detection evaluation ----------------------------------------------

function testCountsAndReasonsForBothRules(~)
cfg = default_config();
ann = make_ann('S1', {'contact', 'contact', 'dry_swing', 'handling', 'contact', 'frame_tap'}, ...
    [1 2 3 4 5 6], [1.2 2.2 3.2 4.2 5.2 6.2]);
% 1.10 TP, 1.25 duplicate (outside a1 but within tau), 2.15 TP, 3.10 in a dry
% swing, 4.05 in a handling action, 7.50 spurious; a5 is missed, a6 rejected.
r = fake_det('S1', [1.10 1.25 2.15 3.10 4.05 7.50], logical([1 0 1 0 0 0]));
ev = vs_evaluate_detection({r}, ann, cfg);
p = ev.rules(1);
assert(strcmp(p.name, 'piezo_only') && p.tp == 2 && p.fp == 4 && p.fn == 1);
assert(abs(p.precision - 2/6) < 1e-12 && abs(p.recall - 2/3) < 1e-12);
assert(abs(p.f1 - 2 * (2/6) * (2/3) / (2/6 + 2/3)) < 1e-12);
assert(p.fp_duplicate == 1 && p.fp_in_dry_swing == 1 && p.fp_in_handling == 1 && p.fp_spurious == 1);
assert(p.frame_tap_correct_rejections == 1 && p.dry_swing_correct_rejections == 0);
assert(~p.meets_precision_target && ~p.meets_recall_target);
q = ev.rules(2);
assert(strcmp(q.name, 'imu_confirmed') && q.tp == 2 && q.fp == 0 && q.fn == 1 && q.precision == 1);
assert(q.dry_swing_correct_rejections == 1 && q.handling_correct_rejections == 1);
rows = strcmp(ev.actions.rule, 'piezo_only');
assert(isequal(ev.actions.outcome(rows), {'TP'; 'TP'; 'detected'; 'detected'; 'FN'; 'correct_rejection'}));
assert(isempty(ev.warnings) && ~ev.synthetic);
end

function testTieBetweenTwoActionsIsAmbiguous(~)
cfg = default_config();
cfg.evaluation.match_tolerance_s = 0.3;
ann = make_ann('S1', {'contact', 'dry_swing'}, [1.0 1.75], [1.25 2.0]);
r = fake_det('S1', [1.5 1.125], true(1, 2));
ev = vs_evaluate_detection({r}, ann, cfg);
p = ev.rules(1);
assert(p.tp == 1 && p.fp == 1 && p.fp_ambiguous == 1 && p.n_ambiguous == 1);
assert(~isempty(ev.warnings), 'tau above half the gap between actions must warn');
end

function testOneToOneMatchingPrefersTheClosestDetection(~)
cfg = default_config();
ann = make_ann('S1', {'contact'}, 1.0, 1.2);
r = fake_det('S1', [0.95 1.10], true(1, 2));  % 0.95 is 50 ms early, 1.10 inside
ev = vs_evaluate_detection({r}, ann, cfg);
rows = strcmp(ev.detections.rule, 'piezo_only');
assert(isequal(ev.detections.outcome(rows), {'FP'; 'TP'}));
assert(strcmp(ev.detections.reason{find(rows, 1)}, 'duplicate'));
end

function testUndefinedRatiosAreNaN(~)
cfg = default_config();
ann = make_ann('S1', {'contact', 'dry_swing'}, [1 2], [1.2 2.2]);
ev = vs_evaluate_detection({fake_det('S1', [], false(1, 0))}, ann, cfg);
p = ev.rules(1);
assert(p.tp == 0 && p.fn == 1 && isnan(p.precision) && p.recall == 0 && isnan(p.f1));
ann = make_ann('S1', {'dry_swing'}, 2, 2.2);
ev = vs_evaluate_detection({fake_det('S1', 5, true)}, ann, cfg);
assert(ev.rules(1).precision == 0 && isnan(ev.rules(1).recall) && isnan(ev.rules(1).f1));
end

function testOnlyEvaluationDataIsScored(~)
cfg = default_config();
ann = make_ann('S1', {'contact'}, 1, 1.2);
r = fake_det('S1', 1.1, true);
r.meta.split = 'tuning';
expect_error(@() vs_evaluate_detection({r}, ann, cfg), 'vs_evaluate_detection:split');
r.meta.split = 'evaluation';
ann.split = {'test'};
expect_error(@() vs_evaluate_detection({r}, ann, cfg), 'vs_evaluate_detection:split');
ann = make_ann('S2', {'contact'}, 1, 1.2);
expect_error(@() vs_evaluate_detection({r}, ann, cfg), 'vs_evaluate_detection:unannotated');
end

function testUnrecordedSessionContactsAreMissed(~)
cfg = default_config();
ann = make_ann('S1', {'contact'}, 1, 1.2);
ann = join_ann(ann, make_ann('S2', {'contact', 'dry_swing'}, [1 2], [1.2 2.2]));
ev = vs_evaluate_detection({fake_det('S1', 1.1, true)}, ann, cfg);
assert(ev.rules(1).tp == 1 && ev.rules(1).fn == 1, 'The S2 contact is missed, not dropped');
assert(ev.rules(1).dry_swing_correct_rejections == 1);
assert(~isempty(strfind(ev.warnings{1}, 'no recording')));
end

function testGyroRuleNotEvaluatedWithoutThreshold(~)
cfg = default_config();
ann = make_ann('S1', {'contact'}, 1, 1.2);
r = fake_det('S1', 1.1, false);
r.det.swing_evaluated = false;
ev = vs_evaluate_detection({r}, ann, cfg);
assert(ev.rules(1).evaluated && ~ev.rules(2).evaluated && ~isempty(ev.rules(2).note));
end

function testSyntheticDistractorsEndToEnd(~)
cfg = default_config();
cfg.detect.noise_floor_threshold = 0.005;     % test values for the synthetic
cfg.detect.swing_confirm_threshold_dps = 60;  % noise, not measured
spec = distractor_spec();
spec.out_dir = tempname();
mkdir(spec.out_dir);
c = onCleanup(@() rmdir(spec.out_dir, 's')); %#ok<NASGU>
info = make_synthetic_fixture(spec);
ann = vs_read_annotations(make_synthetic_annotations(info.folder));
res = vs_process_session(info.folder, cfg);
ev = vs_evaluate_detection({res}, ann, cfg);
assert(ev.synthetic && ~isempty(strfind(ev.label, 'SYNTHETIC')));
p = ev.rules(1);
q = ev.rules(2);
assert(p.tp == 6 && p.fn == 0 && p.fp == 3 && p.fp_in_handling == 3, ...
    'Piezo-only: TP %d FP %d FN %d', p.tp, p.fp, p.fn);
assert(p.dry_swing_correct_rejections == 2 && p.handling_correct_rejections == 2);
assert(q.tp == 6 && q.fp == 0 && q.fn == 0 && q.handling_correct_rejections == 5);
assert(isempty(ev.warnings));
end

% ---- Helpers ------------------------------------------------------------

function r = fake_shots(sid, role, rms, swing)
n = numel(rms);
r.meta = struct('session_id', sid, 'session_type', role);
if strcmp(role, 'stroke')
    r.meta.participant = 'P01';
    r.meta.block = sid(end);
end
r.role = role;
r.synthetic = false;
r.shots.shot = (1:n).';
r.shots.accepted = true(n, 1);
r.shots.status = repmat({'accepted'}, n, 1);
r.shots.rms_v = rms(:);
r.shots.rms_valid = true(n, 1);
r.shots.rms_flags = repmat({''}, n, 1);
r.shots.preimpact_peak_dps = swing(:);
r.shots.preimpact_valid = true(n, 1);
r.shots.preimpact_flags = repmat({''}, n, 1);
end

function r = fake_det(sid, t_s, confirmed)
r.meta = struct('session_id', sid, 'session_type', 'movement', 'split', 'evaluation');
r.role = 'movement';
r.synthetic = false;
r.det.onset_t_us = round(t_s(:) * 1e6);
r.det.swing_confirmed = confirmed(:);
r.det.swing_evaluated = true;
r.qc.status = 'clean';
r.qc.flags = {};
r.qc.piezo.missing_pct = 0;
r.qc.imu.missing_pct = 0;
r.qc.piezo.clipped_pct = 0;
r.qc.imu.n_gyro_clipped = 0;
end

function ann = make_ann(sid, cats, t0, t1)
n = numel(cats);
ann.action_id = (1:n).';
ann.category = cats(:);
ann.t_start_s = t0(:);
ann.t_end_s = t1(:);
ann.session = repmat({sid}, n, 1);
ann.split = repmat({'evaluation'}, n, 1);
end

function a = join_ann(a, b)
f = fieldnames(a);
for i = 1:numel(f)
    a.(f{i}) = [a.(f{i}); b.(f{i})];
end
end

function f = write_tmp(txt)
f = [tempname() '.csv'];
fid = fopen(f, 'w');
fwrite(fid, txt);
fclose(fid);
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
