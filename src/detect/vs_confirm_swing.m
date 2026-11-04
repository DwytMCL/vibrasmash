function det = vs_confirm_swing(det, rec, qc, pre, cfg)
%VS_CONFIRM_SWING Pre-impact gyroscope confirmation of piezo detections.
%
%   det = vs_confirm_swing(det, rec, qc, pre, cfg)
%
%   For each detection, takes the peak filtered angular-speed magnitude in
%   the cfg.features.preimpact_window_s (250 ms) before the onset and
%   confirms the detection when it reaches
%   cfg.detect.swing_confirm_threshold_dps. That threshold is a pilot value
%   (proposal: "established from pilot dry swings and real strokes"); when
%   it is empty, nothing is confirmed and det.swing_evaluated is false,
%   unless cfg.detect.swing_confirm_enabled is true, which is then an error.
%
%   Adds det.swing_peak_dps, det.swing_window_complete, det.swing_confirmed
%   and det.swing_evaluated.
%
%   Tests: tests/unit/test_detect.m

n = numel(det.onset_idx);
thr = cfg.detect.swing_confirm_threshold_dps;
det.swing_peak_dps = nan(n, 1);
det.swing_window_complete = false(n, 1);
det.swing_confirmed = false(n, 1);
det.swing_evaluated = ~isempty(thr);
if isempty(thr)
    if cfg.detect.swing_confirm_enabled
        error('vs_confirm_swing:threshold', ['detect.swing_confirm_enabled is true but ' ...
            'detect.swing_confirm_threshold_dps is not set (a pilot value).']);
    end
    return
end

w = vs_angular_speed(pre.gyro_dps);
invalid = qc.imu.mask.nan | qc.imu.mask.gyro_clipped | pre.imu.mask.not_filtered;
for j = 1:n
    in_rec = rec.imu.record_id == det.record_id(j);
    p = vs_preimpact_peak(rec.imu.t_us(in_rec), w(in_rec), det.onset_t_us(j), ...
        cfg.features.preimpact_window_s, qc.imu.measured_fs_hz, invalid(in_rec));
    det.swing_peak_dps(j) = p.peak_dps;
    det.swing_window_complete(j) = p.complete;
    det.swing_confirmed(j) = p.peak_dps >= thr;
end
end
