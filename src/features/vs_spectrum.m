function s = vs_spectrum(x, fs_hz, form)
%VS_SPECTRUM One-sided Hann-windowed amplitude spectrum of one window.
%
%   s = vs_spectrum(x, fs_hz, form)
%
%   x       the N samples of the window (proposal: N = 2048), no NaN
%   fs_hz   MEASURED sampling rate of the recording, used to label the bins
%   form    'periodic' (default) or 'symmetric' Hann window
%
%   s.freq_hz   bin frequencies k * fs_hz / N, k = 0 .. N/2
%   s.amp       one-sided amplitude, divided by the window's coherent gain
%               (sum of the weights / N), so a sine of amplitude A that
%               falls on a bin centre reads A (units of x)
%   s.peak_hz   frequency of the largest bin from k = 2 upward; a Hann
%               window spreads any DC offset into bins 0 and 1 only
%   s.df_hz     bin spacing, fs_hz / N
%
%   The spectrum is an exploratory diagnostic (proposal); nothing is
%   scored from it. No zero-padding: the caller must pass exactly N samples.
%
%   Tests: tests/unit/test_features.m

if nargin < 3 || isempty(form)
    form = 'periodic';
end
x = x(:);
N = numel(x);
if mod(N, 2) ~= 0
    error('vs_spectrum:length', 'Window length must be even (got %d)', N);
end
if any(isnan(x))
    error('vs_spectrum:nan', 'The window contains NaN samples');
end
n = (0:N-1).';
switch form
    case 'periodic'
        w = 0.5 - 0.5 * cos(2 * pi * n / N);
    case 'symmetric'
        w = 0.5 - 0.5 * cos(2 * pi * n / (N - 1));
    otherwise
        error('vs_spectrum:form', 'form must be periodic or symmetric');
end
X = fft(x .* w);
X = X(1:N/2 + 1);
amp = abs(X) / sum(w);
amp(2:end-1) = 2 * amp(2:end-1);
s.freq_hz = (0:N/2).' * fs_hz / N;
s.amp = amp;
s.df_hz = fs_hz / N;
[~, k] = max(amp(3:end));
s.peak_hz = s.freq_hz(k + 2);
end
