function tests = test_pipeline
%TEST_PIPELINE End-to-end test of run_vibrasmash on SYNTHETIC sessions.
%   Runs scripts/demo_synthetic into a temporary folder and checks every
%   output file and the synthetic labelling. The counts checked here
%   describe the software on planted test events, not a measurement.
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
vs_setup();
out = tempname();
mkdir(out);
testCase.TestData.out = out;
% Figures are not drawn inside the test framework (plots = false); see
% docs/stage8_test_record.txt. The plotting code is exercised by demo_synthetic.
testCase.TestData.run = demo_synthetic(out, false);
end

function teardownOnce(testCase)
rmdir(testCase.TestData.out, 's');
end

function testRunFolderAndReadmeAreLabelledSynthetic(testCase)
run = testCase.TestData.run;
[~, name] = fileparts(run.folder);
assert(strncmp(name, 'synthetic_', 10) && run.synthetic);
assert(~isempty(strfind(fileread(fullfile(run.folder, 'README.txt')), 'SYNTHETIC TEST DATA')));
end

function testEveryListedOutputExists(testCase)
run = testCase.TestData.run;
for i = 1:numel(run.outputs)
    d = dir(run.outputs{i});
    assert(numel(d) == 1 && d.bytes > 0, 'Missing or empty: %s', run.outputs{i});
end
end

function testShotsCsvRowsAndLabels(testCase)
run = testCase.TestData.run;
[hdr, rows] = read_csv(fullfile(run.folder, 'shots.csv'));
assert(size(rows, 1) == 36, '10 controlled + 13 + 13 stroke detections, got %d', size(rows, 1));
src = rows(:, strcmp(hdr, 'data_source'));
assert(all(strcmp(src, 'SYNTHETIC')));
acc = rows(:, strcmp(hdr, 'accepted'));
assert(sum(strcmp(acc, 'false')) == 6, 'The six handling bumps are rejected shots');
end

function testReferenceShotsIndexMedianIs100(testCase)
run = testCase.TestData.run;
idx = run.reference_results{1}.shots.intensity_index;
assert(abs(median(idx) - 100) < 1e-9);
assert(strcmp(run.ref.status, 'ok') && run.ref.n_valid == 10);
end

function testBlocksCsvMatchesShotValues(testCase)
run = testCase.TestData.run;
[hdr, rows] = read_csv(fullfile(run.folder, 'blocks.csv'));
assert(size(rows, 1) == 3);
r = run.results{2};
v = r.shots.rms_v(r.shots.rms_valid);
cv = str2double(rows{2, strcmp(hdr, 'rms_cv_pct')});
assert(abs(cv - 100 * std(v) / mean(v)) < 1e-6, 'CSV CV matches the shot values');
assert(strcmp(rows{1, strcmp(hdr, 'swing_status')}, 'stationary_session'));
assert(isempty(rows{1, strcmp(hdr, 'swing_cv_pct')}), 'Not computed is written empty');
end

function testEvaluationSummaryForBothRules(testCase)
run = testCase.TestData.run;
[hdr, rows] = read_csv(fullfile(run.folder, 'evaluation_summary.csv'));
col = @(name) rows(:, strcmp(hdr, name));
assert(isequal(col('name'), {'piezo_only'; 'imu_confirmed'}));
assert(isequal(str2double(col('tp')), [20; 20]) && isequal(str2double(col('fn')), [0; 0]));
assert(isequal(str2double(col('fp_in_handling')), [6; 0]));
assert(isequal(str2double(col('dry_swing_correct_rejections')), [4; 4]));
assert(all(strcmp(col('data_source'), 'SYNTHETIC')));
end

function testSpectraUseMeasuredRateBins(testCase)
run = testCase.TestData.run;
[hdr, rows] = read_csv(fullfile(run.folder, 'spectra', 'synthetic_demo_reference.csv'));
assert(size(rows, 1) == 1025 && numel(hdr) == 11);
fs = run.reference_results{1}.qc.piezo.measured_fs_hz;
assert(abs(str2double(rows{2, 1}) - fs / 2048) < 1e-6);
end

function testRunLogRecordsSettingsInputsAndLabels(testCase)
run = testCase.TestData.run;
txt = fileread(fullfile(run.folder, 'run_log.txt'));
assert(~isempty(strfind(txt, 'SYNTHETIC TEST DATA')));
assert(~isempty(regexp(txt, 'detect\.noise_floor_threshold\s+= 0\.005\s+\[pilot\]\s+<-- CHANGED', 'once')), ...
    'Pilot values set by the caller are marked');
assert(~isempty(strfind(txt, 'RMS_ref_v = ')));
n_inputs = numel(regexp(txt, 'sha256=([0-9a-f]{64}|unavailable)'));
assert(n_inputs == numel(run.inputs) && n_inputs == 14, '4 sessions x 3 files + 2 annotation files');
end

function testRunWithoutReferenceLeavesIndexEmpty(testCase)
run0 = testCase.TestData.run;
cfg = run0.cfg;
opts.sessions = {run0.results{1}.folder};
opts.cfg = cfg;
opts.out_root = testCase.TestData.out;
opts.label = 'noref';
opts.plots = false;
run = run_vibrasmash(opts);
assert(all(isnan(run.results{1}.shots.intensity_index)));
assert(all(strcmp(run.results{1}.shots.index_note, 'no_reference')));
assert(any(~cellfun(@isempty, strfind(run.warnings, 'No reference'))));
end

function testRunRefusesWithoutSessions(~)
try
    run_vibrasmash(struct('sessions', {{}}));
    error('test:noError', 'Expected an error');
catch err
    assert(strcmp(err.identifier, 'run_vibrasmash:noSessions'), err.message);
end
end

function [hdr, rows] = read_csv(f)
% Minimal reader for the files this project writes (no quoted commas in
% the columns checked here).
txt = fileread(f);
lines = regexp(txt, '\r?\n', 'split');
lines = lines(~cellfun(@isempty, lines));
hdr = strsplit(lines{1}, ',');
rows = cell(numel(lines) - 1, numel(hdr));
for i = 2:numel(lines)
    rows(i - 1, :) = strsplit(lines{i}, ',', 'CollapseDelimiters', false);
end
end
