function env = vs_moving_rms(x, n_win, alignment, segments)
%VS_MOVING_RMS Moving RMS envelope, computed within each segment.
%
%   env = vs_moving_rms(x, n_win, alignment)
%   env = vs_moving_rms(x, n_win, alignment, segments)
%
%   x          N-by-1 signal
%   n_win      window length in samples (proposal: 5 ms)
%   alignment  'trailing'  env(i) uses samples i-n_win+1 .. i
%              'centered'  env(i) uses samples i-floor(n_win/2) .. i+n_win-1-floor(n_win/2)
%   segments   K-by-2 [first last] runs (default: the whole signal). The
%              window never reaches outside its run; near a run edge it is
%              shortened and the RMS uses only the samples present.
%              Samples outside every run are NaN.
%
%   RMS = sqrt((1/N) sum x[n]^2), as in the proposal.
%
%   Tests: tests/unit/test_detect.m

n = numel(x);
if nargin < 4 || isempty(segments)
    segments = [1 n];
end
switch alignment
    case 'trailing'
        lo = -(n_win - 1);
        hi = 0;
    case 'centered'
        lo = -floor(n_win / 2);
        hi = n_win - 1 - floor(n_win / 2);
    otherwise
        error('vs_moving_rms:alignment', 'alignment must be trailing or centered');
end

env = nan(n, 1);
for k = 1:size(segments, 1)
    i0 = segments(k, 1);
    i1 = segments(k, 2);
    v = x(i0:i1);
    v = v(:);
    m = numel(v);
    c = [0; cumsum(v.^2)];
    i = (1:m).';
    a = max(1, i + lo);
    b = min(m, i + hi);
    env(i0:i1) = sqrt((c(b + 1) - c(a)) ./ (b - a + 1));
end
end
