function tests = test_read_recording
%TEST_READ_RECORDING Unit tests for vs_read_recording, vs_read_meta, vs_read_csv_table.
%   All inputs are synthetic fixtures written to temporary folders.
tests = functiontests(localfunctions);
end

function setupOnce(~)
vs_setup();
end

% ---- Normal reading ------------------------------------------------------

function testReadsSyntheticFixture(~)
[info, c] = generate(struct('name', 'read')); %#ok<ASGLU>
rec = vs_read_recording(info.folder);
assert(numel(rec.piezo.t_us) == 100000 && numel(rec.imu.t_us) == 1000);
assert(rec.synthetic);
assert(strcmp(rec.recording_mode, 'continuous'));
assert(all(rec.piezo.record_id == 0) && all(rec.imu.record_id == 0));
assert(isequal(size(rec.imu.gyro_raw), [1000 3]) && isequal(size(rec.imu.accel_raw), [1000 3]));
end

function testUnitConversionsFollowDocumentedFormulas(~)
[info, c] = generate(struct('name', 'units')); %#ok<ASGLU>
rec = vs_read_recording(info.folder);
assert(max(abs(rec.piezo.v - rec.piezo.adc_raw * 3300 / 4095 / 1000)) < 1e-12);
assert(max(max(abs(rec.imu.gyro_dps - rec.imu.gyro_raw / 16.4))) < 1e-12);
assert(max(max(abs(rec.imu.accel_g - rec.imu.accel_raw / 2048))) < 1e-12);
assert(rec.piezo.t_s(1) == 0 && rec.imu.t_s(1) == 0);
assert(abs(rec.piezo.t_s(2) - 50e-6) < 1e-12);
assert(~isempty(strfind(rec.conversion.piezo, 'linear approximation')));
end

function testCalibratedMillivoltColumnIsPreferred(~)
[info, c] = generate(struct('name', 'mv')); %#ok<ASGLU>
T = vs_read_csv_table(info.files.piezo);
write_csv(info.files.piezo, {'t_us', 'adc_raw', 'adc_mv'}, [T.t_us T.adc_raw T.adc_raw * 0.8]);
rec = vs_read_recording(info.folder);
assert(max(abs(rec.piezo.v - rec.piezo.adc_raw * 0.8 / 1000)) < 1e-12);
assert(~isempty(strfind(rec.conversion.piezo, 'adc_mv')));
end

function testColumnOrderDoesNotMatter(~)
[info, c] = generate(struct('name', 'order')); %#ok<ASGLU>
before = vs_read_recording(info.folder);
T = vs_read_csv_table(info.files.imu);
write_csv(info.files.imu, {'gz_raw', 'az_raw', 't_us', 'gy_raw', 'ax_raw', 'gx_raw', 'ay_raw'}, ...
    [T.gz_raw T.az_raw T.t_us T.gy_raw T.ax_raw T.gx_raw T.ay_raw]);
after = vs_read_recording(info.folder);
assert(isequal(before.imu.gyro_raw, after.imu.gyro_raw));
assert(isequal(before.imu.accel_raw, after.imu.accel_raw));
assert(isequal(before.imu.t_us, after.imu.t_us));
end

function testWindowsLineEndingsAreRead(~)
[info, c] = generate(struct('name', 'crlf')); %#ok<ASGLU>
before = vs_read_recording(info.folder);
txt = fileread(info.files.piezo);
write_text(info.files.piezo, strrep(txt, sprintf('\n'), sprintf('\r\n')));
txt = fileread(info.files.meta);
write_text(info.files.meta, strrep(txt, sprintf('\n'), sprintf('\r\n')));
after = vs_read_recording(info.folder);
assert(isequal(before.piezo.t_us, after.piezo.t_us));
assert(isequal(before.piezo.adc_raw, after.piezo.adc_raw));
assert(strcmp(after.meta.recording_mode, 'continuous'));
end

function testRowsKeepFileOrder(~)
[info, c] = generate(struct('name', 'fileorder')); %#ok<ASGLU>
T = vs_read_csv_table(info.files.piezo);
X = T.data;
X([500 501], :) = X([501 500], :);
write_csv(info.files.piezo, T.header, X);
rec = vs_read_recording(info.folder);
assert(rec.piezo.t_us(500) > rec.piezo.t_us(501), 'Rows must not be sorted by the reader');
end

function testTriggeredModeReadsRecordIds(~)
[info, c] = generate(struct('name', 'trig', 'recording_mode', 'triggered')); %#ok<ASGLU>
rec = vs_read_recording(info.folder);
assert(isequal(unique(rec.piezo.record_id).', [1 2 3]));
assert(isequal(unique(rec.imu.record_id).', [1 2 3]));
end

% ---- Inputs that cannot be interpreted are errors ------------------------

function testMissingMetaKeyIsAnError(~)
[info, c] = generate(struct('name', 'nokey')); %#ok<ASGLU>
remove_line(info.files.meta, 'gyro_range_dps');
expect_error(@() vs_read_recording(info.folder), 'vs_read_recording:metaMissing', 'gyro_range_dps');
end

function testDuplicateMetaKeyIsAnError(~)
[info, c] = generate(struct('name', 'dupkey')); %#ok<ASGLU>
append_text(info.files.meta, sprintf('afe_gain = 20\n'));
expect_error(@() vs_read_recording(info.folder), 'vs_read_meta:duplicateKey', 'afe_gain');
end

function testUnsupportedFormatVersionIsAnError(~)
[info, c] = generate(struct('name', 'version')); %#ok<ASGLU>
replace_text(info.files.meta, 'format_version = 1', 'format_version = 2');
expect_error(@() vs_read_recording(info.folder), 'vs_read_recording:formatVersion', '');
end

function testUnsupportedGyroRangeIsAnError(~)
[info, c] = generate(struct('name', 'range')); %#ok<ASGLU>
replace_text(info.files.meta, 'gyro_range_dps = 2000', 'gyro_range_dps = 1500');
expect_error(@() vs_read_recording(info.folder), 'vs_imu_sensitivity:gyroRange', '');
end

function testMissingColumnIsAnError(~)
[info, c] = generate(struct('name', 'nocol')); %#ok<ASGLU>
T = vs_read_csv_table(info.files.imu);
write_csv(info.files.imu, T.header(1:6), T.data(:, 1:6));
expect_error(@() vs_read_recording(info.folder), 'vs_read_recording:missingColumn', 'az_raw');
end

function testTriggeredModeWithoutRecordIdIsAnError(~)
[info, c] = generate(struct('name', 'norecid')); %#ok<ASGLU>
replace_text(info.files.meta, 'recording_mode = continuous', 'recording_mode = triggered');
expect_error(@() vs_read_recording(info.folder), 'vs_read_recording:missingColumn', 'record_id');
end

function testNonNumericContentIsAnError(~)
[info, c] = generate(struct('name', 'text')); %#ok<ASGLU>
append_text(info.files.piezo, sprintf('9999999,abc\n'));
expect_error(@() vs_read_recording(info.folder), 'vs_read_csv_table:nonNumeric', 'abc');
end

function testMissingFileIsAnError(~)
[info, c] = generate(struct('name', 'nofile')); %#ok<ASGLU>
delete(info.files.imu);
expect_error(@() vs_read_recording(info.folder), 'vs_read_recording:missingFile', 'imu.csv');
end

% ---- Helpers ------------------------------------------------------------

function [info, cleanup] = generate(spec)
spec.out_dir = tempname();
mkdir(spec.out_dir);
cleanup = onCleanup(@() rmdir(spec.out_dir, 's'));
info = make_synthetic_fixture(spec);
end

function expect_error(fn, id, text)
try
    fn();
catch err
    assert(strcmp(err.identifier, id), 'Expected error %s, got %s: %s', id, err.identifier, err.message);
    assert(isempty(text) || ~isempty(strfind(err.message, text)), ...
        'Error message should mention "%s": %s', text, err.message);
    return
end
error('test:noError', 'Expected error %s, but none was raised', id);
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

function append_text(file, txt)
fid = fopen(file, 'a');
fwrite(fid, txt);
fclose(fid);
end

function replace_text(file, old, new)
txt = fileread(file);
assert(~isempty(strfind(txt, old)), 'Fixture does not contain "%s"', old);
write_text(file, strrep(txt, old, new));
end

function remove_line(file, key)
lines = strsplit(fileread(file), sprintf('\n'));
keep = cellfun(@(s) isempty(regexp(s, ['^' key '\s*='], 'once')), lines);
write_text(file, strjoin(lines(keep), sprintf('\n')));
end
