function F = vs_design_filters(cfg, piezo_fs_hz, imu_fs_hz)
%VS_DESIGN_FILTERS Butterworth designs from the proposal, at measured rates.
%
%   F = vs_design_filters(cfg, piezo_fs_hz, imu_fs_hz)
%
%   Designs, with butter() at the MEASURED sampling rates:
%     F.piezo_hp   high-pass, cfg.filter.piezo_hp_order at piezo_hp_cutoff_hz
%     F.piezo_lp   low-pass,  cfg.filter.piezo_lp_order at piezo_lp_cutoff_hz
%     F.gyro_lp    low-pass,  cfg.filter.gyro_lp_order  at gyro_lp_cutoff_hz
%   Each has fields b, a, order, cutoff_hz, fs_hz, type. The order is per
%   pass (proposal): applied forward and backward, each filter's magnitude
%   response is squared, giving -6.02 dB at the cutoff instead of -3.01 dB.
%   The high-pass and low-pass are kept as separate designs, not merged into
%   one band-pass.
%
%   Errors if a cutoff is not below the Nyquist frequency of its stream.
%
%   Tests: tests/unit/test_preprocess.m

F.piezo_hp = design(cfg.filter.piezo_hp_order, cfg.filter.piezo_hp_cutoff_hz, piezo_fs_hz, 'high');
F.piezo_lp = design(cfg.filter.piezo_lp_order, cfg.filter.piezo_lp_cutoff_hz, piezo_fs_hz, 'low');
F.gyro_lp = design(cfg.filter.gyro_lp_order, cfg.filter.gyro_lp_cutoff_hz, imu_fs_hz, 'low');
end

function f = design(order, cutoff_hz, fs_hz, type)
if ~(isfinite(fs_hz) && fs_hz > 0)
    error('vs_design_filters:rate', 'Sampling rate must be a positive number, got %g', fs_hz);
end
wn = cutoff_hz / (fs_hz / 2);
if wn >= 1
    error('vs_design_filters:nyquist', ...
        'Cutoff %g Hz is not below the Nyquist frequency %g Hz', cutoff_hz, fs_hz / 2);
end
[f.b, f.a] = butter(order, wn, type);
f.order = order;
f.cutoff_hz = cutoff_hz;
f.fs_hz = fs_hz;
f.type = type;
end
