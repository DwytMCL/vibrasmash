function pre = vs_preprocess(rec, qc, cfg)
%VS_PREPROCESS Bias removal and the proposal's Butterworth filters.
%
%   pre = vs_preprocess(rec, qc, cfg)
%
%   rec from vs_read_recording, qc from vs_validate_recording, cfg from
%   default_config. Returns:
%     pre.piezo.x_biasfree   bias-removed piezo signal (V at the ADC pin)
%     pre.piezo.x            ... then high-pass 80 Hz and low-pass 2 kHz
%     pre.piezo.bias         per-record bias estimates (vs_remove_bias)
%     pre.gyro_dps           N-by-3 gyro, low-pass 20 Hz (deg/s); no offset
%                            removal, because the proposal specifies none
%     pre.filters            the designs used (vs_design_filters)
%     pre.<stream>.segments  contiguous runs that were filtered independently
%     pre.<stream>.mask.near_edge  samples within filter.padding_s of a run
%                            edge, where filtering is least reliable
%     pre.<stream>.mask.not_filtered  samples left NaN (invalid, or in a
%                            run too short to filter)
%     pre.notes              anything the caller should know
%
%   Filters are designed at the measured sampling rates in qc, not the
%   nominal rates. Runs are split at record boundaries, gaps, timestamp
%   errors and NaN samples, so nothing is filtered across a discontinuity.
%   Timestamps and sample counts are unchanged.
%
%   Tests: tests/unit/test_preprocess.m

pre.filters = vs_design_filters(cfg, qc.piezo.measured_fs_hz, qc.imu.measured_fs_hz);
pre.notes = {};

% ---- Piezo
[x0, pre.piezo.bias] = vs_remove_bias(rec, cfg);
pre.piezo.x_biasfree = x0;
seg = vs_contiguous_segments(rec.piezo.record_id, ...
    qc.piezo.mask.after_gap | qc.piezo.mask.time_error, qc.piezo.mask.nan | isnan(x0));
pad = round(cfg.filter.padding_s * qc.piezo.measured_fs_hz);
[pre.piezo.x, info] = vs_filter_padded(x0, [pre.filters.piezo_hp, pre.filters.piezo_lp], pad, seg);
pre.piezo.segments = seg;
pre.piezo.pad_n = pad;
pre.piezo.mask.near_edge = edge_mask(numel(x0), seg, pad);
pre.piezo.mask.not_filtered = isnan(pre.piezo.x);
if ~isempty(info.too_short)
    pre.notes{end+1} = sprintf('%d piezo run(s) too short to filter were left as NaN', ...
        numel(info.too_short));
end

% ---- Gyro
seg = vs_contiguous_segments(rec.imu.record_id, ...
    qc.imu.mask.after_gap | qc.imu.mask.time_error, qc.imu.mask.nan);
pad = round(cfg.filter.padding_s * qc.imu.measured_fs_hz);
[pre.gyro_dps, info] = vs_filter_padded(rec.imu.gyro_dps, pre.filters.gyro_lp, pad, seg);
pre.imu.segments = seg;
pre.imu.pad_n = pad;
pre.imu.mask.near_edge = edge_mask(numel(rec.imu.t_us), seg, pad);
pre.imu.mask.not_filtered = any(isnan(pre.gyro_dps), 2);
if ~isempty(info.too_short)
    pre.notes{end+1} = sprintf('%d IMU run(s) too short to filter were left as NaN', ...
        numel(info.too_short));
end
if qc.imu.dt_p95_us - qc.imu.dt_p05_us > 0.1 * 1e6 / qc.imu.measured_fs_hz
    pre.notes{end+1} = ['IMU timestamps vary by more than 10% of the sample period; ' ...
        'filtering assumes uniform sampling'];
end
end

function m = edge_mask(n, seg, pad)
m = false(n, 1);
for k = 1:size(seg, 1)
    i0 = seg(k, 1);
    i1 = seg(k, 2);
    m(i0:min(i1, i0 + pad - 1)) = true;
    m(max(i0, i1 - pad + 1):i1) = true;
end
end
