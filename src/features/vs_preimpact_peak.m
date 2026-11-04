function p = vs_preimpact_peak(imu_t_us, w, onset_t_us, window_s, imu_fs_hz, invalid)
%VS_PREIMPACT_PEAK Peak angular speed in the window before one impact onset.
%
%   p = vs_preimpact_peak(imu_t_us, w, onset_t_us, window_s, imu_fs_hz, invalid)
%
%   imu_t_us    IMU timestamps (us), original values
%   w           angular-speed magnitude per IMU sample (vs_angular_speed)
%   onset_t_us  detected piezo onset time (us), same clock
%   window_s    proposal: 0.250 s
%   imu_fs_hz   measured IMU rate, for the completeness check
%   invalid     optional logical mask of IMU samples to treat as unusable
%               (clipped, NaN, after a gap, near a filter edge)
%
%   The window is [onset - window_s, onset). IMU samples are selected by
%   timestamp; nothing is interpolated, so the peak time resolution is one
%   IMU sample period (about 5 ms at 200 samples/s).
%
%   p.peak_dps, p.peak_t_us     peak value and its sample time (NaN if none)
%   p.n_samples                 samples in the window
%   p.complete                  false if the IMU data starts or ends more
%                               than 1.5 sample periods inside the window
%   p.touches_invalid           true if any window sample is in 'invalid'
%
%   Tests: tests/unit/test_detect.m

if nargin < 6 || isempty(invalid)
    invalid = false(size(imu_t_us));
end
t0 = onset_t_us - window_s * 1e6;
sel = find(imu_t_us >= t0 & imu_t_us < onset_t_us);
dt = 1e6 / imu_fs_hz;
p.n_samples = numel(sel);
p.touches_invalid = any(invalid(sel));
if isempty(sel)
    p.peak_dps = NaN;
    p.peak_t_us = NaN;
    p.complete = false;
    return
end
p.complete = min(imu_t_us(sel)) <= t0 + 1.5 * dt && max(imu_t_us(sel)) >= onset_t_us - 1.5 * dt;
ws = w(sel);
[p.peak_dps, i] = max(ws);
if isnan(p.peak_dps)
    p.peak_t_us = NaN;
else
    p.peak_t_us = imu_t_us(sel(i));
end
end
