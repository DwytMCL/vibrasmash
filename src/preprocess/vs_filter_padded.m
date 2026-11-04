function [y, info] = vs_filter_padded(x, filters, pad_n, segments)
%VS_FILTER_PADDED Zero-phase filtering on padded contiguous segments.
%
%   [y, info] = vs_filter_padded(x, filters, pad_n)
%   [y, info] = vs_filter_padded(x, filters, pad_n, segments)
%
%   x         N-by-C signal (each column filtered independently)
%   filters   struct array or cell array of structs with fields b and a,
%             applied one after another with filtfilt (forward and backward)
%   pad_n     odd-reflection padding length in samples, per side, capped at
%             (segment length - 1)
%   segments  K-by-2 [first last] sample indices of contiguous runs; default
%             is the whole signal as one segment. Samples outside every
%             segment come back as NaN.
%
%   Each segment is padded on both sides by odd reflection about its end
%   samples (2*x(1) - x(k+1), ...), filtered, and trimmed back. Segments are
%   filtered independently, so nothing is smeared across a gap. filtfilt's
%   own internal edge extension is only 3*(filter length - 1) samples, which
%   is too short for an 80 Hz high-pass at 20 kHz; the explicit padding is
%   the proposal's "padded event record".
%
%   Segments with fewer than info.min_segment_samples samples cannot be
%   filtered reliably and are returned as NaN; their indices are listed in
%   info.too_short.
%
%   Tests: tests/unit/test_preprocess.m

if isstruct(filters)
    filters = num2cell(filters);
end
n = size(x, 1);
if nargin < 4 || isempty(segments)
    segments = [1 n];
end

% filtfilt needs more than 3*(filter length - 1) samples; require that
% for the unpadded segment so even an unpadded fallback would be valid.
max_len = max(cellfun(@(f) max(numel(f.b), numel(f.a)), filters));
info.min_segment_samples = 3 * (max_len - 1) + 1;
info.pad_n = pad_n;
info.too_short = [];

y = nan(size(x));
for k = 1:size(segments, 1)
    i0 = segments(k, 1);
    i1 = segments(k, 2);
    m = i1 - i0 + 1;
    if m < info.min_segment_samples
        info.too_short(end+1, 1) = k;
        continue
    end
    p = min(pad_n, m - 1);
    seg = x(i0:i1, :);
    head = 2 * seg(1, :) - seg(p+1:-1:2, :);
    tail = 2 * seg(end, :) - seg(end-1:-1:end-p, :);
    z = [head; seg; tail];
    for j = 1:numel(filters)
        for c = 1:size(z, 2)
            z(:, c) = filtfilt(filters{j}.b, filters{j}.a, z(:, c));
        end
    end
    y(i0:i1, :) = z(p+1:p+m, :);
end
end
