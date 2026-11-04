function out = make_synthetic_fixture(spec)
%MAKE_SYNTHETIC_FIXTURE Write a labelled SYNTHETIC session folder for testing.
%
%   spec = make_synthetic_fixture()      returns the default specification
%   info = make_synthetic_fixture(spec)  writes a session folder, returns info
%
%   The folder follows the ESP32 input contract (docs/data_format.md) so the
%   importer can be tested before real recordings exist. Every output is
%   marked as synthetic in four ways: the folder name starts with
%   'synthetic_', meta.txt has 'synthetic = true' and a warning comment,
%   session_type is 'synthetic', and a synthetic_truth.csv file lists the
%   planted events. Nothing this function writes is a measurement, and it
%   refuses to write inside the project's data/ folder, which is reserved
%   for real recordings.
%
%   Signal model (all amplitudes and shapes are arbitrary test values, not
%   estimates of real racket behaviour):
%     piezo  ADC input = bias + Gaussian noise + one exponentially decaying
%            sinusoid per event with piezo_amp_mv > 0, starting exactly at
%            the event time; quantised to adc_bits and clipped to the ADC range.
%     gyro   Gaussian noise on each axis + one Gaussian-shaped swing per event
%            with gyro_peak_dps > 0, peaking gyro_lead_s before the event,
%            along the unit vector gyro_axis; quantised with the MPU-6050
%            sensitivity and clipped to signed 16-bit.
%     accel  1 g on z + Gaussian noise (recorded, not used by the outputs).
%
%   Fault injection (for testing validation in Stage 3):
%     piezo_drop_s, imu_drop_s   K-by-2 [start end] times (s) whose samples are removed
%     piezo_duplicate_s          times (s) whose nearest piezo row is written twice
%     imu_jitter_us              standard deviation of IMU timestamp jitter
%     piezo_fs_hz, imu_fs_hz     actual rates; may differ from the nominal rates
%
%   recording_mode 'continuous' writes every sample. 'triggered' keeps only
%   records from pre_trigger_s before to post_trigger_s after each event that
%   has a piezo burst, as the ESP32 circular buffer would; events without a
%   burst (dry swings) then have no record.
%
%   Session role (for testing later stages):
%     synthetic_role   '' (default), or a session type such as 'reference',
%                      'controlled' or 'stroke'. Written as
%                      'synthetic_role = ...'; session_type stays
%                      'synthetic' and split stays 'test', so the folder is
%                      still labelled synthetic everywhere. vs_session_role
%                      uses it in place of session_type.
%     meta_extra       struct of extra meta.txt keys, for example
%                      struct('condition', 'middle', 'block', '1'). Keys that
%                      carry the synthetic labelling cannot be overridden.
%
%   Random numbers come from rng(spec.seed, 'twister') and the caller's
%   generator state is restored afterwards. The same seed gives identical
%   files on the same platform; MATLAB and Octave streams may differ.
%
%   Example:
%     spec = make_synthetic_fixture();
%     spec.out_dir = tempdir;
%     info = make_synthetic_fixture(spec);
%
%   Tests: tests/unit/test_synthetic_fixture.m

defaults = default_spec();
if nargin < 1
    out = defaults;
    return
end

spec = merge_defaults(spec, defaults);
spec.events = merge_event_defaults(spec.events, defaults.events(1));
check_spec(spec);

root = fileparts(fileparts(mfilename('fullpath')));
data_dir = normalise_path(fullfile(root, 'data'));
out_dir = normalise_path(spec.out_dir);
if strncmpi(out_dir, data_dir, numel(data_dir))
    error('make_synthetic_fixture:dataFolder', ...
        'Refusing to write synthetic data inside %s, which is reserved for real recordings.', ...
        fullfile(root, 'data'));
end

folder = fullfile(spec.out_dir, ['synthetic_' spec.name]);
if ~exist(folder, 'dir')
    mkdir(folder);
end

saved_rng = rng();
restore_rng = onCleanup(@() rng(saved_rng));
rng(spec.seed, 'twister');

[piezo_t_us, adc] = make_piezo(spec);
[imu_t_us, gyro_raw, accel_raw] = make_imu(spec);

% Faults applied to the continuous streams before any record segmentation.
keep = ~in_ranges(piezo_t_us, spec.piezo_drop_s, spec.clock_start_us);
piezo_t_us = piezo_t_us(keep);
adc = adc(keep);
keep = ~in_ranges(imu_t_us, spec.imu_drop_s, spec.clock_start_us);
imu_t_us = imu_t_us(keep);
gyro_raw = gyro_raw(keep, :);
accel_raw = accel_raw(keep, :);
for k = 1:numel(spec.piezo_duplicate_s)
    target = spec.clock_start_us + spec.piezo_duplicate_s(k) * 1e6;
    [~, i] = min(abs(piezo_t_us - target));
    piezo_t_us = [piezo_t_us(1:i); piezo_t_us(i:end)];
    adc = [adc(1:i); adc(i:end)];
end

event_onset_us = spec.clock_start_us + round([spec.events.t_s].' * 1e6);
event_record = zeros(numel(spec.events), 1);
piezo_record = [];
imu_record = [];
if strcmp(spec.recording_mode, 'triggered')
    piezo_record = zeros(size(piezo_t_us));
    imu_record = zeros(size(imu_t_us));
    rec = 0;
    for e = 1:numel(spec.events)
        if spec.events(e).piezo_amp_mv > 0
            rec = rec + 1;
            event_record(e) = rec;
            lo = event_onset_us(e) - spec.pre_trigger_s * 1e6;
            hi = event_onset_us(e) + spec.post_trigger_s * 1e6;
            piezo_record(piezo_t_us >= lo & piezo_t_us < hi) = rec;
            imu_record(imu_t_us >= lo & imu_t_us < hi) = rec;
        end
    end
    keep = piezo_record > 0;
    piezo_t_us = piezo_t_us(keep); adc = adc(keep); piezo_record = piezo_record(keep);
    keep = imu_record > 0;
    imu_t_us = imu_t_us(keep); gyro_raw = gyro_raw(keep, :);
    accel_raw = accel_raw(keep, :); imu_record = imu_record(keep);
end

files.piezo = fullfile(folder, 'piezo.csv');
files.imu = fullfile(folder, 'imu.csv');
files.meta = fullfile(folder, 'meta.txt');
files.truth = fullfile(folder, 'synthetic_truth.csv');

write_piezo(files.piezo, piezo_t_us, adc, piezo_record);
write_imu(files.imu, imu_t_us, gyro_raw, accel_raw, imu_record);
write_meta(files.meta, spec);
write_truth(files.truth, spec, event_onset_us, event_record);

out.folder = folder;
out.files = files;
out.n_piezo_rows = numel(piezo_t_us);
out.n_imu_rows = numel(imu_t_us);
out.event_onset_us = event_onset_us;
out.event_record_id = event_record;
out.spec = spec;
end

% -------------------------------------------------------------------------

function spec = default_spec()
spec.name = 'default';
spec.out_dir = tempdir;
spec.seed = 1;
spec.duration_s = 5;
spec.clock_start_us = 1000000;      % non-zero, so code cannot assume t starts at 0
spec.recording_mode = 'continuous';
spec.pre_trigger_s = 0.300;
spec.post_trigger_s = 0.200;

spec.piezo_fs_nominal_hz = 20000;
spec.imu_fs_nominal_hz = 200;
spec.piezo_fs_hz = 20000;           % actual rate written to the file
spec.imu_fs_hz = 200;

spec.adc_bits = 12;
spec.adc_vref_mv = 3300;
spec.adc_attenuation_db = 11;
spec.afe_bias_mv = 1650;
spec.afe_gain = 10;
spec.piezo_noise_mv = 2;

spec.gyro_range_dps = 2000;
spec.accel_range_g = 16;
spec.gyro_noise_dps = 1;
spec.accel_noise_g = 0.01;
spec.gyro_axis = [0.3 0.2 0.93];    % direction of the planted swing (normalised)
spec.imu_jitter_us = 0;

spec.piezo_drop_s = zeros(0, 2);
spec.imu_drop_s = zeros(0, 2);
spec.piezo_duplicate_s = [];

spec.synthetic_role = '';
spec.meta_extra = struct();

% Default events: two contacts, one dry swing, one frame tap.
spec.events = struct( ...
    'category',      {'contact', 'contact', 'dry_swing', 'frame_tap'}, ...
    't_s',           {1.0,       2.0,       3.0,         4.0}, ...
    'piezo_amp_mv',  {300,       250,       0,           80}, ...
    'piezo_freq_hz', {750,       750,       750,         1200}, ...
    'piezo_decay_s', {0.015,     0.015,     0.015,       0.005}, ...
    'gyro_peak_dps', {150,       120,       140,         0}, ...
    'gyro_lead_s',   {0.060,     0.060,     0.060,       0.060}, ...
    'gyro_width_s',  {0.040,     0.040,     0.040,       0.040});
end

function spec = merge_defaults(spec, defaults)
names = fieldnames(defaults);
for i = 1:numel(names)
    if ~isfield(spec, names{i})
        spec.(names{i}) = defaults.(names{i});
    end
end
end

function events = merge_event_defaults(events, template)
names = fieldnames(template);
for i = 1:numel(names)
    if ~isfield(events, names{i})
        [events.(names{i})] = deal(template.(names{i}));
    end
end
end

function check_spec(spec)
if ~ischar(spec.name) || isempty(regexp(spec.name, '^[A-Za-z0-9_-]+$', 'once'))
    error('make_synthetic_fixture:name', 'spec.name must use letters, digits, _ or - only');
end
if ~any(strcmp(spec.recording_mode, {'continuous', 'triggered'}))
    error('make_synthetic_fixture:mode', 'recording_mode must be continuous or triggered');
end
valid = {'contact', 'dry_swing', 'handling', 'frame_tap'};
for e = 1:numel(spec.events)
    if ~any(strcmp(spec.events(e).category, valid))
        error('make_synthetic_fixture:category', ...
            'Event %d: category must be one of %s', e, strjoin(valid, ', '));
    end
end
reserved = {'format_version', 'synthetic', 'session_id', 'session_type', 'split', ...
    'recording_mode', 'synthetic_role'};
bad = intersect(fieldnames(spec.meta_extra), reserved);
if ~isempty(bad)
    error('make_synthetic_fixture:metaExtra', 'meta_extra cannot set %s', strjoin(bad, ', '));
end
t = [spec.events.t_s];
if ~all(t > 0 & t < spec.duration_s)
    error('make_synthetic_fixture:eventTime', 'Event times must lie inside the recording');
end
if strcmp(spec.recording_mode, 'triggered')
    tb = sort(t([spec.events.piezo_amp_mv] > 0));
    if any(diff(tb) < spec.pre_trigger_s + spec.post_trigger_s)
        error('make_synthetic_fixture:overlap', 'Triggered records would overlap');
    end
end
end

function [t_us, adc] = make_piezo(spec)
n = floor(spec.duration_s * spec.piezo_fs_hz);
t = (0:n-1).' / spec.piezo_fs_hz;
mv = spec.afe_bias_mv + spec.piezo_noise_mv * randn(n, 1);
for e = 1:numel(spec.events)
    ev = spec.events(e);
    if ev.piezo_amp_mv > 0
        idx = t >= ev.t_s;
        dt = t(idx) - ev.t_s;
        mv(idx) = mv(idx) + ev.piezo_amp_mv * exp(-dt / ev.piezo_decay_s) ...
            .* sin(2 * pi * ev.piezo_freq_hz * dt);
    end
end
full_scale = 2^spec.adc_bits - 1;
adc = min(max(round(mv / spec.adc_vref_mv * full_scale), 0), full_scale);
t_us = spec.clock_start_us + round(t * 1e6);
end

function [t_us, gyro_raw, accel_raw] = make_imu(spec)
n = floor(spec.duration_s * spec.imu_fs_hz);
t = (0:n-1).' / spec.imu_fs_hz;
axis_dir = spec.gyro_axis / norm(spec.gyro_axis);
gyro = spec.gyro_noise_dps * randn(n, 3);
for e = 1:numel(spec.events)
    ev = spec.events(e);
    if ev.gyro_peak_dps > 0
        bump = ev.gyro_peak_dps * exp(-0.5 * ((t - (ev.t_s - ev.gyro_lead_s)) / ev.gyro_width_s).^2);
        gyro = gyro + bump * axis_dir;
    end
end
accel = repmat([0 0 1], n, 1) + spec.accel_noise_g * randn(n, 3);
[sg, sa] = vs_imu_sensitivity(spec.gyro_range_dps, spec.accel_range_g);
gyro_raw = min(max(round(gyro * sg), -32768), 32767);
accel_raw = min(max(round(accel * sa), -32768), 32767);
jitter = spec.imu_jitter_us * randn(n, 1);
t_us = spec.clock_start_us + round(t * 1e6 + jitter);
end

function tf = in_ranges(t_us, ranges_s, start_us)
tf = false(size(t_us));
for k = 1:size(ranges_s, 1)
    lo = start_us + ranges_s(k, 1) * 1e6;
    hi = start_us + ranges_s(k, 2) * 1e6;
    tf = tf | (t_us >= lo & t_us < hi);
end
end

function p = normalise_path(p)
p = strrep(p, '\', '/');
while numel(p) > 1 && p(end) == '/'
    p = p(1:end-1);
end
end

function write_piezo(file, t_us, adc, record)
fid = fopen(file, 'w');
closer = onCleanup(@() fclose(fid));
if isempty(record)
    fprintf(fid, 't_us,adc_raw\n');
    fprintf(fid, '%d,%d\n', [t_us adc].');
else
    fprintf(fid, 't_us,adc_raw,record_id\n');
    fprintf(fid, '%d,%d,%d\n', [t_us adc record].');
end
end

function write_imu(file, t_us, gyro, accel, record)
fid = fopen(file, 'w');
closer = onCleanup(@() fclose(fid));
if isempty(record)
    fprintf(fid, 't_us,gx_raw,gy_raw,gz_raw,ax_raw,ay_raw,az_raw\n');
    fprintf(fid, '%d,%d,%d,%d,%d,%d,%d\n', [t_us gyro accel].');
else
    fprintf(fid, 't_us,gx_raw,gy_raw,gz_raw,ax_raw,ay_raw,az_raw,record_id\n');
    fprintf(fid, '%d,%d,%d,%d,%d,%d,%d,%d\n', [t_us gyro accel record].');
end
end

function write_meta(file, spec)
fid = fopen(file, 'w');
closer = onCleanup(@() fclose(fid));
fprintf(fid, '# SYNTHETIC TEST DATA generated by make_synthetic_fixture.m\n');
fprintf(fid, '# Not a measurement. Must never be reported as an experimental result.\n');
fprintf(fid, 'format_version = 1\n');
fprintf(fid, 'synthetic = true\n');
fprintf(fid, 'session_id = synthetic_%s\n', spec.name);
fprintf(fid, 'session_type = synthetic\n');
fprintf(fid, 'split = test\n');
fprintf(fid, 'recording_mode = %s\n', spec.recording_mode);
if strcmp(spec.recording_mode, 'triggered')
    fprintf(fid, 'pre_trigger_s = %g\n', spec.pre_trigger_s);
end
fprintf(fid, 'piezo_fs_nominal_hz = %g\n', spec.piezo_fs_nominal_hz);
fprintf(fid, 'imu_fs_nominal_hz = %g\n', spec.imu_fs_nominal_hz);
fprintf(fid, 'piezo_timestamp_mode = per_sample\n');
fprintf(fid, 'adc_bits = %d\n', spec.adc_bits);
fprintf(fid, 'adc_vref_mv = %g\n', spec.adc_vref_mv);
fprintf(fid, 'adc_attenuation_db = %g\n', spec.adc_attenuation_db);
fprintf(fid, 'afe_bias_mv = %g\n', spec.afe_bias_mv);
fprintf(fid, 'afe_gain = %g\n', spec.afe_gain);
fprintf(fid, 'gyro_range_dps = %g\n', spec.gyro_range_dps);
fprintf(fid, 'accel_range_g = %g\n', spec.accel_range_g);
fprintf(fid, 'mount_id = synthetic\n');
fprintf(fid, 'racket_id = synthetic\n');
fprintf(fid, 'clock_source = synthetic\n');
if ~isempty(spec.synthetic_role)
    fprintf(fid, 'synthetic_role = %s\n', spec.synthetic_role);
end
extra = fieldnames(spec.meta_extra);
for i = 1:numel(extra)
    fprintf(fid, '%s = %s\n', extra{i}, num2str(spec.meta_extra.(extra{i})));
end
fprintf(fid, '# Generator parameters (ground truth for tests)\n');
fprintf(fid, 'synthetic_seed = %d\n', spec.seed);
fprintf(fid, 'synthetic_piezo_fs_hz = %g\n', spec.piezo_fs_hz);
fprintf(fid, 'synthetic_imu_fs_hz = %g\n', spec.imu_fs_hz);
fprintf(fid, 'synthetic_piezo_noise_mv = %g\n', spec.piezo_noise_mv);
fprintf(fid, 'synthetic_gyro_noise_dps = %g\n', spec.gyro_noise_dps);
fprintf(fid, 'synthetic_imu_jitter_us = %g\n', spec.imu_jitter_us);
end

function write_truth(file, spec, onset_us, record)
fid = fopen(file, 'w');
closer = onCleanup(@() fclose(fid));
fprintf(fid, ['event_id,category,t_onset_us,piezo_amp_mv,piezo_freq_hz,piezo_decay_s,' ...
              'gyro_peak_dps,gyro_lead_s,gyro_width_s,record_id\n']);
for e = 1:numel(spec.events)
    ev = spec.events(e);
    fprintf(fid, '%d,%s,%d,%g,%g,%g,%g,%g,%g,%d\n', e, ev.category, onset_us(e), ...
        ev.piezo_amp_mv, ev.piezo_freq_hz, ev.piezo_decay_s, ev.gyro_peak_dps, ...
        ev.gyro_lead_s, ev.gyro_width_s, record(e));
end
end
