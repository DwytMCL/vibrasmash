function w = vs_window_check(i0, n, ctx)
%VS_WINDOW_CHECK Completeness and contamination of one piezo feature window.
%
%   w = vs_window_check(i0, n, ctx)
%
%   i0    index of the first sample (the detected onset)
%   n     number of samples the window must hold
%   ctx   per-sample context for the piezo stream, built by vs_shot_features:
%           record_id, after_gap, time_error, clipped, invalid (NaN or not
%           filtered), near_edge ([] when the signal was not filtered),
%           envelope, threshold_v (the onset's record threshold),
%           second_event_ratio and envelope_window_samples
%
%   w.complete   true if samples i0 .. i0+n-1 exist and all belong to the
%                onset's record; nothing is zero-padded or borrowed from
%                the next record
%   w.idx        the window's sample indices (empty if incomplete)
%   w.flags      cell array of codes, empty when the window is clean:
%                  incomplete       fewer than n samples left in the record
%                  gap              a timestamp gap or timing error inside
%                  clipped          an ADC sample at the clipping limits
%                  padding          a sample within the filter edge zone
%                  invalid_samples  a NaN or unfiltered sample
%                  second_event     the envelope crosses the threshold
%                                   upward again inside the window AND
%                                   reaches second_event_ratio x threshold
%                                   within one envelope window after that
%                                   crossing. Smaller re-crossings are the
%                                   decaying tail of the same ringing
%                                   hovering at the threshold, which the
%                                   proposal's refractory interval already
%                                   treats as one event.
%
%   docs/settings_provenance.md, section 3, gives the rules.
%
%   Tests: tests/unit/test_features.m

w.flags = {};
w.idx = [];
i1 = i0 + n - 1;
N = numel(ctx.record_id);
w.complete = i1 <= N && all(ctx.record_id(i0:min(i1, N)) == ctx.record_id(i0));
if ~w.complete
    w.flags = {'incomplete'};
    return
end
idx = (i0:i1).';
w.idx = idx;
if any(ctx.after_gap(idx(2:end))) || any(ctx.time_error(idx))
    w.flags{end+1} = 'gap';
end
if any(ctx.clipped(idx))
    w.flags{end+1} = 'clipped';
end
if ~isempty(ctx.near_edge) && any(ctx.near_edge(idx))
    w.flags{end+1} = 'padding';
end
if any(ctx.invalid(idx))
    w.flags{end+1} = 'invalid_samples';
end
env = ctx.envelope(idx);
above = env >= ctx.threshold_v;
cross = find(above(2:end) & ~above(1:end-1)) + 1;
for c = cross.'
    look = env(c:min(numel(env), c + ctx.envelope_window_samples - 1));
    if max(look) >= ctx.second_event_ratio * ctx.threshold_v
        w.flags{end+1} = 'second_event';
        break
    end
end
end
