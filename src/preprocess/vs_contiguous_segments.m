function segments = vs_contiguous_segments(record_id, break_before, invalid)
%VS_CONTIGUOUS_SEGMENTS Runs of valid samples that may be filtered together.
%
%   segments = vs_contiguous_segments(record_id, break_before, invalid)
%
%   record_id     N-by-1 record id per sample
%   break_before  N-by-1 logical; true where a new run must start (for
%                 example the first sample after a gap or a timestamp error)
%   invalid       N-by-1 logical; samples excluded from every run (NaN)
%
%   Returns K-by-2 [first last] indices. A run never spans a record
%   boundary, a break or an invalid sample.
%
%   Tests: tests/unit/test_preprocess.m

n = numel(record_id);
valid = ~invalid(:);
starts = false(n, 1);
ends = false(n, 1);
for i = 1:n
    if ~valid(i)
        continue
    end
    starts(i) = i == 1 || ~valid(i-1) || record_id(i) ~= record_id(i-1) || break_before(i);
    ends(i) = i == n || ~valid(i+1) || record_id(i+1) ~= record_id(i) || break_before(i+1);
end
segments = [find(starts) find(ends)];
end
