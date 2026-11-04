function tests = test_synthetic_fixture
%TEST_SYNTHETIC_FIXTURE Unit tests for scripts/make_synthetic_fixture.m.
%   All data here is generated synthetic test input, written to temporary
%   folders and deleted afterwards. None of it is a measurement.
tests = functiontests(localfunctions);
end

function setupOnce(~)
vs_setup();
end

% ---- Labelling ---------------------------------------------------------

function testNoArgumentReturnsDefaultSpecOnly(~)
spec = make_synthetic_fixture();
assert(isstruct(spec) && isfield(spec, 'events') && isfield(spec, 'seed'));
end

function testFolderAndMetaAreLabelledSynthetic(~)
[info, cleanup] = generate(struct('name', 'labels')); %#ok<ASGLU>
[~, folder_name] = fileparts(info.folder);
assert(strncmp(folder_name, 'synthetic_', 10));
meta = fileread(info.files.meta);
assert(~isempty(strfind(meta, 'SYNTHETIC TEST DATA')));
assert(~isempty(regexp(meta, 'synthetic = true', 'once')));
assert(~isempty(regexp(meta, 'session_type = synthetic', 'once')));
assert(exist(info.files.truth, 'file') == 2);
end

function testRefusesToWriteInsideDataFolder(~)
root = fileparts(which('vs_setup'));
threw = false;
try
    make_synthetic_fixture(struct('name', 'forbidden', 'out_dir', fullfile(root, 'data', 'raw')));
catch err
    threw = strcmp(err.identifier, 'make_synthetic_fixture:dataFolder');
end
assert(threw, 'Writing synthetic data into data/ must be refused');
assert(exist(fullfile(root, 'data', 'raw', 'synthetic_forbidden'), 'dir') ~= 7);
end

function testRejectsUnknownEventCategory(~)
spec = make_synthetic_fixture();
spec.name = 'badcat';
spec.out_dir = tempdir;
spec.events(1).category = 'smash';
threw = false;
try
    make_synthetic_fixture(spec);
catch err
    threw = strcmp(err.identifier, 'make_synthetic_fixture:category');
end
assert(threw);
end

% ---- Files load as plain CSV in the documented layout -------------------

function testPiezoCsvLoadsAsPlainCsv(~)
[info, cleanup] = generate(struct('name', 'piezo')); %#ok<ASGLU>
[hdr, X] = read_numeric_csv(info.files.piezo);
assert(isequal(hdr, {'t_us', 'adc_raw'}));
assert(size(X, 1) == 5 * 20000);
assert(all(X(:) == round(X(:))), 'All values must be integers');
assert(all(diff(X(:,1)) == 50), '20 kHz gives 50 us spacing');
assert(X(1,1) == 1000000, 'Clock starts at clock_start_us');
assert(min(X(:,2)) >= 0 && max(X(:,2)) <= 4095);
end

function testImuCsvLoadsAsPlainCsv(~)
[info, cleanup] = generate(struct('name', 'imu')); %#ok<ASGLU>
[hdr, X] = read_numeric_csv(info.files.imu);
assert(isequal(hdr, {'t_us', 'gx_raw', 'gy_raw', 'gz_raw', 'ax_raw', 'ay_raw', 'az_raw'}));
assert(size(X, 1) == 5 * 200);
assert(all(diff(X(:,1)) == 5000), '200 Hz gives 5000 us spacing');
assert(all(all(X(:,2:7) >= -32768 & X(:,2:7) <= 32767)));
end

function testTruthFileListsPlantedEvents(~)
[info, cleanup] = generate(struct('name', 'truth')); %#ok<ASGLU>
T = read_truth(info.files.truth);
assert(isequal(T.category, {'contact'; 'contact'; 'dry_swing'; 'frame_tap'}));
assert(isequal(T.t_onset_us, [2e6; 3e6; 4e6; 5e6]));
assert(isequal(T.record_id, [0; 0; 0; 0]), 'Continuous mode has no records');
end

% ---- Planted signals are where the truth file says ----------------------

function testPiezoBurstStartsAtOnsetWithPlantedAmplitude(~)
[info, cleanup] = generate(struct('name', 'burst')); %#ok<ASGLU>
[~, X] = read_numeric_csv(info.files.piezo);
spec = info.spec;
counts_per_mv = (2^spec.adc_bits - 1) / spec.adc_vref_mv;
bias = round(spec.afe_bias_mv * counts_per_mv);
noise_counts = spec.piezo_noise_mv * counts_per_mv;
t = X(:,1); x = X(:,2) - bias;
onset = info.event_onset_us(1);

before = t >= onset - 50000 & t < onset;
assert(max(abs(x(before))) < 6 * noise_counts + 1, 'Signal before onset must be noise only');

after = t >= onset & t < onset + 5000;
expected = spec.events(1).piezo_amp_mv * counts_per_mv;
peak = max(abs(x(after)));
assert(abs(peak - expected) / expected < 0.08, ...
    'Peak %.1f counts, expected about %.1f', peak, expected);
end

function testGyroPeakPrecedesImpactByPlantedLead(~)
[info, cleanup] = generate(struct('name', 'gyro')); %#ok<ASGLU>
[~, X] = read_numeric_csv(info.files.imu);
spec = info.spec;
sg = vs_imu_sensitivity(spec.gyro_range_dps);
t = X(:,1);
w = sqrt(sum((X(:,2:4) / sg).^2, 2));
for e = 1:3                      % two contacts and the dry swing have swings
    onset = info.event_onset_us(e);
    win = t >= onset - 250000 & t < onset;
    [peak, i] = max(w(win));
    tw = t(win);
    assert(abs(peak - spec.events(e).gyro_peak_dps) < 5, 'Event %d peak %.1f', e, peak);
    assert(abs((onset - tw(i)) - spec.events(e).gyro_lead_s * 1e6) <= 5000, ...
        'Event %d peak timing', e);
end
onset = info.event_onset_us(4);  % frame tap: no swing planted
win = t >= onset - 250000 & t < onset;
assert(max(w(win)) < 10);
end

function testLargeBurstClipsAtAdcLimits(~)
spec = make_synthetic_fixture();
spec.name = 'clip';
spec.events(1).piezo_amp_mv = 3000;
[info, cleanup] = generate(spec); %#ok<ASGLU>
[~, X] = read_numeric_csv(info.files.piezo);
assert(min(X(:,2)) == 0 && max(X(:,2)) == 4095);
end

% ---- Faults for the validation stage ------------------------------------

function testDroppedSamplesLeaveTimestampGap(~)
[info, cleanup] = generate(struct('name', 'drop', 'piezo_drop_s', [1.5 1.6])); %#ok<ASGLU>
[~, X] = read_numeric_csv(info.files.piezo);
assert(size(X, 1) == 5 * 20000 - 2000);
d = diff(X(:,1));
assert(max(d) == 100050 && sum(d ~= 50) == 1);
end

function testDuplicateTimestampIsWritten(~)
[info, cleanup] = generate(struct('name', 'dup', 'piezo_duplicate_s', 2.5)); %#ok<ASGLU>
[~, X] = read_numeric_csv(info.files.piezo);
assert(size(X, 1) == 5 * 20000 + 1);
assert(sum(diff(X(:,1)) == 0) == 1);
end

function testActualRateCanDifferFromNominal(~)
[info, cleanup] = generate(struct('name', 'rate', 'piezo_fs_hz', 19000)); %#ok<ASGLU>
[~, X] = read_numeric_csv(info.files.piezo);
assert(abs(mean(diff(X(:,1))) - 1e6 / 19000) < 0.01);
meta = fileread(info.files.meta);
assert(~isempty(regexp(meta, 'piezo_fs_nominal_hz = 20000', 'once')));
assert(~isempty(regexp(meta, 'synthetic_piezo_fs_hz = 19000', 'once')));
end

% ---- Triggered records --------------------------------------------------

function testTriggeredModeKeepsOnlyEventRecords(~)
[info, cleanup] = generate(struct('name', 'trig', 'recording_mode', 'triggered')); %#ok<ASGLU>
[hdr, P] = read_numeric_csv(info.files.piezo);
assert(isequal(hdr, {'t_us', 'adc_raw', 'record_id'}));
[hdr, I] = read_numeric_csv(info.files.imu);
assert(strcmp(hdr{end}, 'record_id'));
T = read_truth(info.files.truth);
assert(isequal(T.record_id, [1; 2; 0; 3]), 'The dry swing has no burst, so no record');
for r = 1:3
    assert(sum(P(:,3) == r) == 0.5 * 20000, 'Record %d piezo rows', r);
    assert(sum(I(:,8) == r) == 0.5 * 200, 'Record %d IMU rows', r);
    onset = T.t_onset_us(T.record_id == r);
    tr = P(P(:,3) == r, 1);
    assert(tr(1) == onset - 300000 && tr(end) == onset + 200000 - 50);
end
end

% ---- Reproducibility ----------------------------------------------------

function testSameSeedGivesIdenticalFiles(~)
[a, ca] = generate(struct('name', 'repeat')); %#ok<ASGLU>
[b, cb] = generate(struct('name', 'repeat')); %#ok<ASGLU>
assert(strcmp(fileread(a.files.piezo), fileread(b.files.piezo)));
assert(strcmp(fileread(a.files.imu), fileread(b.files.imu)));
end

function testDifferentSeedGivesDifferentNoise(~)
[a, ca] = generate(struct('name', 'seed1', 'seed', 1)); %#ok<ASGLU>
[b, cb] = generate(struct('name', 'seed2', 'seed', 2)); %#ok<ASGLU>
assert(~strcmp(fileread(a.files.piezo), fileread(b.files.piezo)));
end

function testCallerRandomStateIsRestored(~)
rng(42, 'twister');
expected = rand();
rng(42, 'twister');
[info, cleanup] = generate(struct('name', 'rngstate')); %#ok<ASGLU>
assert(rand() == expected);
end

% ---- Helpers ------------------------------------------------------------

function [info, cleanup] = generate(spec)
% Write a fixture into a fresh temporary folder that is deleted when
% 'cleanup' goes out of scope.
spec.out_dir = tempname();
mkdir(spec.out_dir);
cleanup = onCleanup(@() rmdir(spec.out_dir, 's'));
info = make_synthetic_fixture(spec);
end

function [hdr, X] = read_numeric_csv(file)
% Plain CSV reader: one header line, then integer/real columns.
fid = fopen(file, 'r');
closer = onCleanup(@() fclose(fid));
hdr = strsplit(fgetl(fid), ',');
C = textscan(fid, repmat('%f', 1, numel(hdr)), 'Delimiter', ',');
X = [C{:}];
end

function T = read_truth(file)
fid = fopen(file, 'r');
closer = onCleanup(@() fclose(fid));
fgetl(fid);
C = textscan(fid, '%f %s %f %f %f %f %f %f %f %f', 'Delimiter', ',');
T.event_id = C{1};
T.category = C{2};
T.t_onset_us = C{3};
T.record_id = C{10};
end
