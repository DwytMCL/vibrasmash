function [thr, stats] = vs_adaptive_threshold(env_background, k_mad, noise_floor)
%VS_ADAPTIVE_THRESHOLD Detection threshold from the background envelope.
%
%   [thr, stats] = vs_adaptive_threshold(env_background, k_mad, noise_floor)
%
%   Proposal: "median background envelope plus six median absolute
%   deviations, with a minimum threshold set above measured electronics
%   noise". So
%       thr = max(median(bg) + k_mad * MAD(bg), noise_floor)
%   with MAD(bg) = median(|bg - median(bg)|), unscaled.
%
%   stats has fields median, mad, statistical_threshold, noise_floor,
%   n_background, limited_by ('statistical' or 'noise_floor'). With no
%   background samples the threshold is NaN.
%
%   Tests: tests/unit/test_detect.m

if isempty(noise_floor) || ~isfinite(noise_floor)
    error('vs_adaptive_threshold:noiseFloor', ...
        'A numeric noise floor is required (proposal: minimum threshold above measured electronics noise)');
end
bg = env_background(~isnan(env_background));
stats.n_background = numel(bg);
stats.noise_floor = noise_floor;
if isempty(bg)
    stats.median = NaN;
    stats.mad = NaN;
    stats.statistical_threshold = NaN;
    stats.limited_by = 'no_background';
    thr = NaN;
    return
end
stats.median = median(bg);
stats.mad = median(abs(bg - stats.median));
stats.statistical_threshold = stats.median + k_mad * stats.mad;
if stats.statistical_threshold >= noise_floor
    thr = stats.statistical_threshold;
    stats.limited_by = 'statistical';
else
    thr = noise_floor;
    stats.limited_by = 'noise_floor';
end
end
