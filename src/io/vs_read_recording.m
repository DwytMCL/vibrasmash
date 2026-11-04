function rec = vs_read_recording(folder)
%VS_READ_RECORDING Read one session folder in the ESP32 format.
%
%   rec = vs_read_recording(folder)
%
%   Reads meta.txt, piezo.csv and imu.csv (docs/data_format.md). Rows are
%   kept in file order with their original timestamps and raw counts;
%   nothing is resampled, interpolated, sorted or removed. Data-quality
%   problems are left for vs_validate_recording to flag.
%
%   This function errors (identifier vs_read_recording:*) only when the
%   files cannot be interpreted at all: a missing file, a missing required
%   metadata key or column, an unsupported format_version, or an unsupported
%   sensor range.
%
%   Unit conversions (all recorded in rec.conversion):
%     piezo.v       volts at the ADC pin: adc_mv / 1000 when the file has an
%                   adc_mv column (ESP-IDF calibration), otherwise the linear
%                   approximation adc_raw * adc_vref_mv / (2^adc_bits - 1) / 1000
%     imu.gyro_dps  gyro_raw / S_g, S_g from vs_imu_sensitivity (datasheet)
%     imu.accel_g   accel_raw / S_a
%     *.t_s         (t_us - t0_us) / 1e6, where t0_us is the earliest
%                   timestamp in either stream, so both streams share one origin
%
%   Tests: tests/unit/test_read_recording.m

files.meta = fullfile(folder, 'meta.txt');
files.piezo = fullfile(folder, 'piezo.csv');
files.imu = fullfile(folder, 'imu.csv');
names = fieldnames(files);
for i = 1:numel(names)
    if exist(files.(names{i}), 'file') ~= 2
        error('vs_read_recording:missingFile', 'Missing %s', files.(names{i}));
    end
end

meta = vs_read_meta(files.meta);
required = {'format_version', 'session_id', 'session_type', 'split', 'recording_mode', ...
    'piezo_fs_nominal_hz', 'imu_fs_nominal_hz', 'piezo_timestamp_mode', 'adc_bits', ...
    'adc_attenuation_db', 'afe_bias_mv', 'afe_gain', 'gyro_range_dps', 'accel_range_g', ...
    'mount_id', 'racket_id', 'clock_source'};
missing = required(~isfield(meta, required));
if ~isempty(missing)
    error('vs_read_recording:metaMissing', 'meta.txt is missing required keys: %s', ...
        strjoin(missing, ', '));
end
if ~strcmp(meta.format_version, '1')
    error('vs_read_recording:formatVersion', 'Unsupported format_version %s (expected 1)', ...
        meta.format_version);
end
check_choice(meta, 'recording_mode', {'continuous', 'triggered'});
check_choice(meta, 'piezo_timestamp_mode', {'per_sample', 'frame_derived'});

P = vs_read_csv_table(files.piezo);
I = vs_read_csv_table(files.imu);
triggered = strcmp(meta.recording_mode, 'triggered');
require_columns(P, {'t_us', 'adc_raw'}, triggered, files.piezo);
require_columns(I, {'t_us', 'gx_raw', 'gy_raw', 'gz_raw', 'ax_raw', 'ay_raw', 'az_raw'}, ...
    triggered, files.imu);

s.adc_bits = meta_number(meta, 'adc_bits');
s.afe_bias_mv = meta_number(meta, 'afe_bias_mv');
s.afe_gain = meta_number(meta, 'afe_gain');
s.gyro_range_dps = meta_number(meta, 'gyro_range_dps');
s.accel_range_g = meta_number(meta, 'accel_range_g');
s.piezo_fs_nominal_hz = meta_number(meta, 'piezo_fs_nominal_hz');
s.imu_fs_nominal_hz = meta_number(meta, 'imu_fs_nominal_hz');
[sg, sa] = vs_imu_sensitivity(s.gyro_range_dps, s.accel_range_g);

rec.folder = folder;
rec.files = files;
rec.meta = meta;
rec.settings = s;
rec.recording_mode = meta.recording_mode;
rec.synthetic = isfield(meta, 'synthetic') && strcmpi(meta.synthetic, 'true');

% Piezo stream
rec.piezo.t_us = P.t_us;
rec.piezo.adc_raw = P.adc_raw;
rec.piezo.record_id = column_or_zeros(P, 'record_id');
if isfield(P, 'adc_mv')
    rec.piezo.v = P.adc_mv / 1000;
    rec.conversion.piezo = 'adc_mv column (calibrated by firmware) / 1000';
else
    if ~isfield(meta, 'adc_vref_mv')
        error('vs_read_recording:metaMissing', ...
            'meta.txt needs adc_vref_mv when piezo.csv has no adc_mv column');
    end
    s.adc_vref_mv = meta_number(meta, 'adc_vref_mv');
    rec.settings = s;
    rec.piezo.v = P.adc_raw * s.adc_vref_mv / (2^s.adc_bits - 1) / 1000;
    rec.conversion.piezo = sprintf(['linear approximation: adc_raw * %g mV / %d / 1000 ' ...
        '(ignores ESP32 ADC non-linearity)'], s.adc_vref_mv, 2^s.adc_bits - 1);
end

% IMU stream
rec.imu.t_us = I.t_us;
rec.imu.gyro_raw = [I.gx_raw I.gy_raw I.gz_raw];
rec.imu.accel_raw = [I.ax_raw I.ay_raw I.az_raw];
rec.imu.record_id = column_or_zeros(I, 'record_id');
rec.imu.gyro_dps = rec.imu.gyro_raw / sg;
rec.imu.accel_g = rec.imu.accel_raw / sa;
rec.conversion.gyro = sprintf('gyro_raw / %g LSB per deg/s (MPU-6050, +/-%g deg/s)', ...
    sg, s.gyro_range_dps);
rec.conversion.accel = sprintf('accel_raw / %g LSB per g (MPU-6050, +/-%g g)', ...
    sa, s.accel_range_g);

% Shared time origin
rec.t0_us = min([rec.piezo.t_us; rec.imu.t_us]);
rec.piezo.t_s = (rec.piezo.t_us - rec.t0_us) / 1e6;
rec.imu.t_s = (rec.imu.t_us - rec.t0_us) / 1e6;
rec.conversion.time = 't_s = (t_us - t0_us) / 1e6, t0_us = earliest timestamp in either stream';
end

% -------------------------------------------------------------------------

function check_choice(meta, key, allowed)
if ~any(strcmp(meta.(key), allowed))
    error('vs_read_recording:metaValue', '%s = %s; expected one of: %s', ...
        key, meta.(key), strjoin(allowed, ', '));
end
end

function v = meta_number(meta, key)
v = str2double(meta.(key));
if isnan(v)
    error('vs_read_recording:metaValue', '%s = "%s" is not a number', key, meta.(key));
end
end

function require_columns(T, cols, need_record_id, file)
if need_record_id
    cols = [cols {'record_id'}];
end
missing = cols(~ismember(cols, T.header));
if ~isempty(missing)
    error('vs_read_recording:missingColumn', '%s is missing columns: %s', ...
        file, strjoin(missing, ', '));
end
end

function x = column_or_zeros(T, name)
if isfield(T, name)
    x = T.(name);
else
    x = zeros(size(T.data, 1), 1);
end
end
