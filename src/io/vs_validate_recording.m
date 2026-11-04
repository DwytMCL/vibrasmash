function qc = vs_validate_recording(rec, cfg)
%VS_VALIDATE_RECORDING Check timing, sampling and clipping; flag, never fix.
%
%   qc = vs_validate_recording(rec, cfg)
%
%   rec is the output of vs_read_recording and cfg of default_config. The
%   recording is not modified. qc reports, per stream (piezo, imu) and per
%   record:
%     - measured sampling rate and its deviation from the nominal rate
%     - timestamps that go backwards or repeat, and microsecond clock wrap
%     - gaps (interval > cfg.sampling.gap_factor x median interval), the
%       estimated number of missing samples, and missing % against the
%       proposal's 1% target
%     - interval spread (5th / 50th / 95th percentile)
%     - NaN values, ADC clipping and IMU (gyro, accel) clipping
%     - records too short to hold both the 250 ms pre-impact window and the
%       2,048-sample FFT window
%     - IMU records that do not cover the matching piezo record
%   Per-sample logical masks (qc.<stream>.mask.*) let later stages check
%   whether a feature window touches a flagged sample.
%
%   qc.flags lists problem codes; qc.notes lists information that is not a
%   problem (synthetic data, frame-derived timestamps). qc.status is 'clean'
%   when qc.flags is empty and 'flagged' otherwise. Nothing is rejected here:
%   accept/reject decisions and their reasons are made and reported later.
%
%   The measured rate is 1e6 x (number of normal intervals) / (sum of normal
%   intervals in us), where normal means positive and not a gap. It is used
%   for all later calculations; the nominal rate is only compared against.
%
%   Tests: tests/unit/test_validate_recording.m

qc.session_id = rec.meta.session_id;
qc.synthetic = rec.synthetic;
qc.flags = {};
qc.notes = {};
qc.settings_used.gap_factor = cfg.sampling.gap_factor;
qc.settings_used.rate_tolerance_pct = cfg.sampling.rate_tolerance_pct;
qc.settings_used.missing_target_pct = cfg.sampling.missing_target_pct;
qc.settings_used.adc_clip_margin_counts = cfg.qc.adc_clip_margin_counts;
qc.settings_used.imu_clip_margin_counts = cfg.qc.imu_clip_margin_counts;

if rec.synthetic
    qc.notes{end+1} = 'synthetic_data: generated test input, not a measurement';
end
if strcmp(rec.meta.piezo_timestamp_mode, 'frame_derived')
    qc.notes{end+1} = ['piezo_timestamps_frame_derived: per-sample piezo times were ' ...
        'computed by the firmware from DMA frame times'];
end

% ---- Timing per stream
[qc.piezo, f] = stream_timing(rec.piezo.t_us, rec.piezo.record_id, ...
    rec.settings.piezo_fs_nominal_hz, cfg, 'piezo');
qc.flags = [qc.flags f];
[qc.imu, f] = stream_timing(rec.imu.t_us, rec.imu.record_id, ...
    rec.settings.imu_fs_nominal_hz, cfg, 'imu');
qc.flags = [qc.flags f];

% ---- Values: NaN and clipping
full_scale = 2^rec.settings.adc_bits - 1;
m = cfg.qc.adc_clip_margin_counts;
qc.piezo.mask.nan = isnan(rec.piezo.adc_raw) | isnan(rec.piezo.t_us) | isnan(rec.piezo.record_id);
qc.piezo.mask.clipped = rec.piezo.adc_raw <= m | rec.piezo.adc_raw >= full_scale - m;
qc.piezo.n_nan = sum(qc.piezo.mask.nan);
qc.piezo.n_clipped = sum(qc.piezo.mask.clipped);
qc.piezo.clipped_pct = 100 * qc.piezo.n_clipped / max(numel(rec.piezo.adc_raw), 1);
qc.piezo.bias_expected_mv = rec.settings.afe_bias_mv;
qc.piezo.bias_measured_mv = 1000 * median(rec.piezo.v(~isnan(rec.piezo.v)));
if qc.piezo.n_nan > 0, qc.flags{end+1} = 'piezo_nan_values'; end
if qc.piezo.n_clipped > 0, qc.flags{end+1} = 'piezo_clipped'; end

mi = cfg.qc.imu_clip_margin_counts;
imu_vals = [rec.imu.gyro_raw rec.imu.accel_raw];
qc.imu.mask.nan = any(isnan(imu_vals), 2) | isnan(rec.imu.t_us) | isnan(rec.imu.record_id);
qc.imu.mask.gyro_clipped = any(rec.imu.gyro_raw <= -32768 + mi | rec.imu.gyro_raw >= 32767 - mi, 2);
qc.imu.mask.accel_clipped = any(rec.imu.accel_raw <= -32768 + mi | rec.imu.accel_raw >= 32767 - mi, 2);
qc.imu.n_nan = sum(qc.imu.mask.nan);
qc.imu.n_gyro_clipped = sum(qc.imu.mask.gyro_clipped);
qc.imu.n_accel_clipped = sum(qc.imu.mask.accel_clipped);
if qc.imu.n_nan > 0, qc.flags{end+1} = 'imu_nan_values'; end
if qc.imu.n_gyro_clipped > 0, qc.flags{end+1} = 'imu_gyro_clipped'; end
if qc.imu.n_accel_clipped > 0, qc.flags{end+1} = 'imu_accel_clipped'; end

% ---- Records: length and IMU coverage
qc.min_record_s = cfg.features.preimpact_window_s + cfg.spectrum.nfft / qc.piezo.measured_fs_hz;
piezo_ids = [qc.piezo.records.record_id];
imu_ids = [qc.imu.records.record_id];
if ~isequal(sort(piezo_ids), sort(imu_ids))
    qc.flags{end+1} = 'record_ids_mismatch';
end
too_short = false;
not_covered = false;
imu_dt_us = 1e6 / qc.imu.measured_fs_hz;
for r = 1:numel(qc.piezo.records)
    pr = qc.piezo.records(r);
    short = pr.duration_s < qc.min_record_s;
    j = find(imu_ids == pr.record_id, 1);
    if isempty(j)
        covers = false;
    else
        ir = qc.imu.records(j);
        covers = ir.t_start_us <= pr.t_start_us + 1.5 * imu_dt_us && ...
                 ir.t_end_us >= pr.t_end_us - 1.5 * imu_dt_us;
    end
    qc.piezo.records(r).too_short = short;
    qc.piezo.records(r).imu_covers = covers;
    too_short = too_short || short;
    not_covered = not_covered || ~covers;
end
if too_short, qc.flags{end+1} = 'record_too_short'; end
if not_covered, qc.flags{end+1} = 'imu_does_not_cover_piezo'; end

qc.flags = unique(qc.flags, 'stable');
if isempty(qc.flags)
    qc.status = 'clean';
else
    qc.status = 'flagged';
end
end

% -------------------------------------------------------------------------

function [s, flags] = stream_timing(t_us, record_id, fs_nominal, cfg, name)
flags = {};
n = numel(t_us);
s.n_samples = n;
s.nominal_fs_hz = fs_nominal;
s.mask.after_gap = false(n, 1);
s.mask.time_error = false(n, 1);

ids = unique(record_id(~isnan(record_id))).';
s.n_records = numel(ids);
n_normal = 0; sum_normal = 0;
all_dt = [];
gaps = zeros(0, 3);
n_back = 0; n_dup = 0; wrap = false; missing_total = 0; few = false;
for k = 1:numel(ids)
    idx = find(record_id == ids(k));
    t = t_us(idx);
    dt = diff(t);
    pos = dt(dt > 0);
    r.record_id = ids(k);
    r.n_samples = numel(idx);
    r.t_start_us = min(t);
    r.t_end_us = max(t);
    r.duration_s = (r.t_end_us - r.t_start_us) / 1e6;
    if isempty(pos)
        few = true;
        r.median_dt_us = NaN;
        r.measured_fs_hz = NaN;
        r.n_gaps = 0;
        r.missing_samples = 0;
    else
        med = median(pos);
        is_gap = dt > cfg.sampling.gap_factor * med;
        normal = dt > 0 & ~is_gap;
        r.median_dt_us = med;
        r.measured_fs_hz = 1e6 * sum(normal) / sum(dt(normal));
        r.n_gaps = sum(is_gap);
        miss = round(dt(is_gap) / med) - 1;
        r.missing_samples = sum(miss);
        gi = find(is_gap);
        gaps = [gaps; t(gi) t(gi + 1) miss]; %#ok<AGROW>
        s.mask.after_gap(idx(gi + 1)) = true;
        n_normal = n_normal + sum(normal);
        sum_normal = sum_normal + sum(dt(normal));
        all_dt = [all_dt; dt(normal)]; %#ok<AGROW>
    end
    bad = find(dt <= 0);
    s.mask.time_error(idx(bad + 1)) = true;
    n_back = n_back + sum(dt < 0);
    n_dup = n_dup + sum(dt == 0);
    wrap = wrap || any(dt < -2^31);      % uint32 microsecond counter rollover
    missing_total = missing_total + r.missing_samples;
    records(k) = r; %#ok<AGROW>
end
if s.n_records == 0
    records = struct('record_id', {}, 'n_samples', {}, 't_start_us', {}, 't_end_us', {}, ...
        'duration_s', {}, 'median_dt_us', {}, 'measured_fs_hz', {}, 'n_gaps', {}, ...
        'missing_samples', {});
end
s.records = records;

if n_normal > 0
    s.measured_fs_hz = 1e6 * n_normal / sum_normal;
    sd = sort(all_dt);
    pick = @(q) sd(max(1, ceil(q * numel(sd))));
    s.dt_p05_us = pick(0.05);
    s.dt_p50_us = pick(0.50);
    s.dt_p95_us = pick(0.95);
else
    s.measured_fs_hz = NaN;
    s.dt_p05_us = NaN; s.dt_p50_us = NaN; s.dt_p95_us = NaN;
end
s.rate_deviation_pct = 100 * (s.measured_fs_hz - fs_nominal) / fs_nominal;
s.n_backwards = n_back;
s.n_duplicates = n_dup;
s.clock_wrap = wrap;
s.gaps = gaps;
s.n_gaps = size(gaps, 1);
s.missing_samples = missing_total;
s.missing_pct = 100 * missing_total / max(n + missing_total, 1);

if n_back > 0, flags{end+1} = [name '_backwards_time']; end
if n_dup > 0, flags{end+1} = [name '_duplicate_time']; end
if wrap, flags{end+1} = [name '_clock_wrap']; end
if s.n_gaps > 0, flags{end+1} = [name '_gaps']; end
if s.missing_pct >= cfg.sampling.missing_target_pct
    flags{end+1} = [name '_missing_above_target'];
end
if isnan(s.measured_fs_hz) || abs(s.rate_deviation_pct) > cfg.sampling.rate_tolerance_pct
    flags{end+1} = [name '_rate_mismatch'];
end
if few, flags{end+1} = [name '_record_too_few_samples']; end
end
