function [cv, m, sd] = vs_cv(x)
%VS_CV Coefficient of variation, CV = 100 x sample standard deviation / mean.
%
%   [cv, m, sd] = vs_cv(x)
%
%   Proposal formula, sample (n - 1) standard deviation. x must hold valid
%   values only; NaN is an error rather than silently skipped. Returns NaN
%   for CV when fewer than two values exist or the mean is not positive
%   (both features are magnitudes, so a non-positive mean means bad input).
%
%   Tests: tests/unit/test_analysis.m

x = x(:);
if any(isnan(x))
    error('vs_cv:nan', 'vs_cv takes valid values only; remove invalid shots first');
end
m = NaN;
sd = NaN;
cv = NaN;
if isempty(x)
    return
end
m = mean(x);
if numel(x) < 2
    return
end
sd = std(x);            % normalised by n - 1
if m > 0
    cv = 100 * sd / m;
end
end
