function tests = test_validate_recording
%TEST_VALIDATE_RECORDING Unit tests for vs_validate_recording and vs_qc_summary.
%   Every fault is planted in a synthetic fixture; each test checks that the
%   validator flags it (or, for clean data, flags nothing) and changes no data.
tests = functiontests(localfunctions);
end

function setupOnce(~)
vs_setup();
end

% ---- Clean data ---------------------------------------------------------

function testCleanContinuousFixtureIsClean(~)
[rec, qc, c] = check(struct('name', 'clean')); %#ok<ASGLU>
assert(strcmp(qc.status, 'clean'), 'Unexpected flags: %s', strjoin(qc.flags, ', '));
assert(abs(qc.piezo.measured_fs_hz - 20000) < 1e-6 && abs(qc.imu.measured_fs_hz - 200) < 1e-9);
assert(qc.piezo.missing_samples == 0 && qc.imu.missing_samples == 0);
assert(abs(qc.min_record_s - (0.25 + 2048 / 20000)) < 1e-12);
assert(numel(qc.piezo.mask.clipped) == numel(rec.piezo.t_us));
assert(any(~cellfun(@isempty, strfind(qc.notes, 'synthetic_data'))));
end

function testCleanTriggeredFixtureIsClean(~)
[~, qc, c] = check(struct('name', 'cleantrig', 'recording_mode', 'triggered')); %#ok<ASGLU>
assert(strcmp(qc.status, 'clean'), 'Unexpected flags: %s', strjoin(qc.flags, ', '));
assert(qc.piezo.n_records == 3 && qc.imu.n_records == 3);
assert(all([qc.piezo.records.imu_covers]) && ~any([qc.piezo.records.too_short]));
assert(qc.piezo.n_gaps == 0, 'Time between triggered records is not a gap');
end

% ---- Timing faults ------------------------------------------------------

function testDroppedSamplesAreCountedNotFilled(~)
[rec, qc, c] = check(struct('name', 'drop', 'piezo_drop_s', [1.5 1.6])); %#ok<ASGLU>
assert_flags(qc, {'piezo_gaps', 'piezo_missing_above_target'});
assert(numel(rec.piezo.t_us) == 98000, 'No samples may be added');
assert(qc.piezo.missing_samples == 2000);
assert(abs(qc.piezo.missing_pct - 2) < 1e-9);
assert(isequal(qc.piezo.gaps, [2499950 2600000 2000]));
assert(sum(qc.piezo.mask.after_gap) == 1 && rec.piezo.t_us(qc.piezo.mask.after_gap) == 2600000);
end

function testSmallGapIsFlaggedButBelowMissingTarget(~)
[~, qc, c] = check(struct('name', 'smalldrop', 'piezo_drop_s', [1.5 1.5005])); %#ok<ASGLU>
assert_flags(qc, {'piezo_gaps'});
assert(qc.piezo.missing_samples == 10);
end

function testDuplicateTimestampIsFlagged(~)
[~, qc, c] = check(struct('name', 'dup', 'piezo_duplicate_s', 2.5)); %#ok<ASGLU>
assert_flags(qc, {'piezo_duplicate_time'});
assert(qc.piezo.n_duplicates == 1 && sum(qc.piezo.mask.time_error) == 1);
end

function testBackwardsTimestampIsFlagged(~)
[info, c] = generate(struct('name', 'back')); %#ok<ASGLU>
T = vs_read_csv_table(info.files.piezo);
X = T.data;
X([500 501], :) = X([501 500], :);
write_csv(info.files.piezo, T.header, X);
qc = vs_validate_recording(vs_read_recording(info.folder), default_config());
assert(any(strcmp(qc.flags, 'piezo_backwards_time')));
assert(qc.piezo.n_backwards == 1);
end

function testClockWrapIsFlagged(~)
[info, c] = generate(struct('name', 'wrap')); %#ok<ASGLU>
T = vs_read_csv_table(info.files.imu);
X = T.data;
X(501:end, 1) = X(501:end, 1) - 2^32;   % uint32 microsecond counter rolled over
write_csv(info.files.imu, T.header, X);
qc = vs_validate_recording(vs_read_recording(info.folder), default_config());
assert(any(strcmp(qc.flags, 'imu_clock_wrap')) && any(strcmp(qc.flags, 'imu_backwards_time')));
end

function testRateMismatchIsFlaggedAndMeasured(~)
[~, qc, c] = check(struct('name', 'rate', 'piezo_fs_hz', 19000)); %#ok<ASGLU>
assert_flags(qc, {'piezo_rate_mismatch'});
assert(abs(qc.piezo.measured_fs_hz - 19000) / 19000 < 1e-3);
assert(abs(qc.piezo.rate_deviation_pct + 5) < 0.1);
end

function testSmallRateDeviationIsWithinTolerance(~)
[~, qc, c] = check(struct('name', 'rateok', 'piezo_fs_hz', 19900)); %#ok<ASGLU>
assert(strcmp(qc.status, 'clean'), 'Unexpected flags: %s', strjoin(qc.flags, ', '));
assert(abs(qc.piezo.measured_fs_hz - 19900) / 19900 < 1e-3);
end

function testImuJitterIsReportedNotFlagged(~)
[~, qc, c] = check(struct('name', 'jitter', 'imu_jitter_us', 200)); %#ok<ASGLU>
assert(strcmp(qc.status, 'clean'), 'Unexpected flags: %s', strjoin(qc.flags, ', '));
assert(qc.imu.dt_p95_us > 5000 && qc.imu.dt_p05_us < 5000);
end

% ---- Value faults -------------------------------------------------------

function testAdcClippingIsFlaggedWithMask(~)
spec = make_synthetic_fixture();
spec.name = 'clip';
spec.events(1).piezo_amp_mv = 3000;
[rec, qc, c] = check(spec); %#ok<ASGLU>
assert_flags(qc, {'piezo_clipped'});
clipped_t = rec.piezo.t_us(qc.piezo.mask.clipped);
assert(all(clipped_t >= info_onset(1) & clipped_t < info_onset(1) + 200000));
end

function testGyroClippingIsFlagged(~)
spec = make_synthetic_fixture();
spec.name = 'gyroclip';
spec.events(1).gyro_peak_dps = 4000;     % beyond the +/-2000 deg/s range
[~, qc, c] = check(spec); %#ok<ASGLU>
assert_flags(qc, {'imu_gyro_clipped'});
assert(qc.imu.n_gyro_clipped > 0 && qc.imu.n_accel_clipped == 0);
end

function testEmptyCellIsFlaggedAsNan(~)
[info, c] = generate(struct('name', 'nan')); %#ok<ASGLU>
lines = strsplit(fileread(info.files.piezo), sprintf('\n'));
parts = strsplit(lines{1001}, ',');
lines{1001} = [parts{1} ','];
write_text(info.files.piezo, strjoin(lines, sprintf('\n')));
rec = vs_read_recording(info.folder);
qc = vs_validate_recording(rec, default_config());
assert(numel(rec.piezo.t_us) == 100000, 'The row must be kept');
assert(any(strcmp(qc.flags, 'piezo_nan_values')) && qc.piezo.n_nan == 1);
end

% ---- Record-level faults ------------------------------------------------

function testShortRecordIsFlagged(~)
spec = struct('name', 'short', 'recording_mode', 'triggered', ...
    'pre_trigger_s', 0.1, 'post_trigger_s', 0.1);
[~, qc, c] = check(spec); %#ok<ASGLU>
assert_flags(qc, {'record_too_short'});
end

function testImuNotCoveringPiezoIsFlagged(~)
[~, qc, c] = check(struct('name', 'cover', 'imu_drop_s', [0 0.5])); %#ok<ASGLU>
assert_flags(qc, {'imu_does_not_cover_piezo'});
end

function testRecordIdMismatchIsFlagged(~)
[info, c] = generate(struct('name', 'ids', 'recording_mode', 'triggered')); %#ok<ASGLU>
T = vs_read_csv_table(info.files.imu);
X = T.data;
X(X(:, end) == 3, end) = 9;
write_csv(info.files.imu, T.header, X);
qc = vs_validate_recording(vs_read_recording(info.folder), default_config());
assert(any(strcmp(qc.flags, 'record_ids_mismatch')));
assert(any(strcmp(qc.flags, 'imu_does_not_cover_piezo')));
end

% ---- Notes and summary --------------------------------------------------

function testFrameDerivedTimestampsAreANoteNotAFlag(~)
[info, c] = generate(struct('name', 'frame')); %#ok<ASGLU>
txt = strrep(fileread(info.files.meta), 'piezo_timestamp_mode = per_sample', ...
    'piezo_timestamp_mode = frame_derived');
write_text(info.files.meta, txt);
qc = vs_validate_recording(vs_read_recording(info.folder), default_config());
assert(strcmp(qc.status, 'clean'));
assert(any(~cellfun(@isempty, strfind(qc.notes, 'frame_derived'))));
end

function testSummaryShowsSyntheticLabelAndFlags(~)
[~, qc, c] = check(struct('name', 'summary', 'piezo_duplicate_s', 2.5)); %#ok<ASGLU>
txt = vs_qc_summary(qc);
assert(~isempty(strfind(txt, 'SYNTHETIC TEST DATA')));
assert(~isempty(strfind(txt, 'piezo_duplicate_time')));
assert(~isempty(strfind(txt, 'Status: flagged')));
end

% ---- Helpers ------------------------------------------------------------

function t = info_onset(k)
% Onset of default event k, in us, for the default clock start of 1 s.
spec = make_synthetic_fixture();
t = spec.clock_start_us + round(spec.events(k).t_s * 1e6);
end

function [rec, qc, cleanup] = check(spec)
[info, cleanup] = generate(spec);
rec = vs_read_recording(info.folder);
qc = vs_validate_recording(rec, default_config());
end

function assert_flags(qc, expected)
% The planted fault, and only the planted fault, is flagged.
assert(isequal(sort(qc.flags), sort(expected)), 'Flags {%s}, expected {%s}', ...
    strjoin(qc.flags, ', '), strjoin(expected, ', '));
assert(strcmp(qc.status, 'flagged'));
end

function [info, cleanup] = generate(spec)
spec.out_dir = tempname();
mkdir(spec.out_dir);
cleanup = onCleanup(@() rmdir(spec.out_dir, 's'));
info = make_synthetic_fixture(spec);
end

function write_csv(file, header, X)
fid = fopen(file, 'w');
fprintf(fid, '%s\n', strjoin(header, ','));
fmt = [strjoin(repmat({'%.10g'}, 1, size(X, 2)), ',') '\n'];
fprintf(fid, fmt, X.');
fclose(fid);
end

function write_text(file, txt)
fid = fopen(file, 'w');
fwrite(fid, txt);
fclose(fid);
end
