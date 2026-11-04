function r = vs_impact_rms(x)
%VS_IMPACT_RMS Root mean square of one window of samples.
%
%   r = vs_impact_rms(x)
%
%   Proposal: RMS = sqrt((1/N) * sum(x[n]^2)) over the N samples of the
%   window. Returns NaN for an empty window or one containing NaN, never a
%   value computed from part of the window.
%
%   Tests: tests/unit/test_features.m

if isempty(x) || any(isnan(x))
    r = NaN;
    return
end
r = sqrt(sum(x(:).^2) / numel(x));
end
