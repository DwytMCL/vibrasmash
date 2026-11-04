function [x, bias] = vs_remove_bias(rec, cfg)
%VS_REMOVE_BIAS Subtract the recorded piezo bias, one estimate per record.
%
%   [x, bias] = vs_remove_bias(rec, cfg)
%
%   x     N-by-1 piezo signal in volts at the ADC pin with the bias removed
%   bias  struct array, one element per record, with fields record_id,
%         bias_v, method, n_samples_used
%
%   The proposal says to "remove the recorded bias" without fixing a method.
%   Provisional methods (cfg.preprocess):
%     triggered records   median of the pre-trigger samples, excluding the
%                         last bias_exclude_before_trigger_s before the
%                         trigger, so the start of the impact is not included
%     continuous records  median of the whole record; a median is not moved
%                         by short impact bursts
%   The pre-trigger length is meta.txt's pre_trigger_s when present,
%   otherwise cfg.record.pre_trigger_s. NaN samples are ignored and stay NaN.
%
%   Tests: tests/unit/test_preprocess.m

v = rec.piezo.v;
t = rec.piezo.t_us;
rid = rec.piezo.record_id;
x = nan(size(v));
pre_s = cfg.record.pre_trigger_s;
if isfield(rec.meta, 'pre_trigger_s')
    pre_s = str2double(rec.meta.pre_trigger_s);
end
use_s = pre_s - cfg.preprocess.bias_exclude_before_trigger_s;

ids = unique(rid(~isnan(rid))).';
bias = struct('record_id', {}, 'bias_v', {}, 'method', {}, 'n_samples_used', {});
for k = 1:numel(ids)
    idx = find(rid == ids(k));
    ok = idx(~isnan(v(idx)));
    if strcmp(rec.recording_mode, 'triggered')
        method = cfg.preprocess.bias_method;
        t_start = min(t(idx));
        sel = ok(t(ok) < t_start + use_s * 1e6);
    else
        method = cfg.preprocess.bias_method_continuous;
        sel = ok;
    end
    if isempty(sel)
        b = NaN;
    else
        b = median(v(sel));
    end
    x(idx) = v(idx) - b;
    bias(k).record_id = ids(k);
    bias(k).bias_v = b;
    bias(k).method = method;
    bias(k).n_samples_used = numel(sel);
end
end
