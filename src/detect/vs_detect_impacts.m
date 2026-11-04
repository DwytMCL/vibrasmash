function det = vs_detect_impacts(rec, qc, pre, cfg)
%VS_DETECT_IMPACTS Piezo impact detection, with optional gyro confirmation.
%
%   det = vs_detect_impacts(rec, qc, pre, cfg)
%
%   Proposal method:
%     1. 5 ms moving RMS envelope of the filtered piezo signal
%        (cfg.detect.envelope_window_s, alignment cfg.detect.envelope_alignment)
%     2. threshold = max(median + 6 x MAD of the background envelope,
%        noise floor), one threshold per record (vs_adaptive_threshold)
%     3. an onset is the first sample where the envelope reaches the
%        threshold after being below it
%     4. 150 ms refractory interval measured from each accepted onset, so one
%        ringing event is counted once
%     5. optional pre-impact gyro confirmation, reported alongside; the
%        piezo-only and combined results are both kept for evaluation
%
%   Background samples: in a triggered record, the pre-trigger part
%   (cfg.detect.background_source = 'pre_trigger', excluding the last
%   preprocess.bias_exclude_before_trigger_s); in a continuous recording,
%   the whole record. Samples near a filter edge or left unfiltered are
%   never background.
%
%   Requires cfg.detect.noise_floor_threshold (volts, a pilot value); errors
%   if it is empty. The gyro confirmation is computed only when
%   cfg.detect.swing_confirm_threshold_dps is set; with
%   cfg.detect.swing_confirm_enabled true it is required.
%
%   det.onset_idx, det.onset_t_us, det.record_id    one row per detection
%   det.peak_envelope_v       envelope maximum within the refractory window
%   det.edge_candidates       crossings inside a filter edge zone, not counted
%   det.swing_peak_dps        pre-impact peak angular speed (NaN if not computed)
%   det.swing_confirmed       logical; all false when not computed
%   det.swing_evaluated       true when the gyro rule was computed
%   det.accepted              detections used downstream: piezo-only, or the
%                             combined rule when swing_confirm_enabled is true
%                             and the session is not a stationary test
%   det.envelope              envelope per piezo sample
%   det.thresholds            per-record threshold statistics
%
%   Tests: tests/unit/test_detect.m

if isempty(cfg.detect.noise_floor_threshold)
    error('vs_detect_impacts:noiseFloor', ['cfg.detect.noise_floor_threshold is not set. ' ...
        'It is a pilot value: measure the envelope of a still-racket recording and set a ' ...
        'minimum threshold above it (proposal, impact detection).']);
end

fs = qc.piezo.measured_fs_hz;
n_win = round(cfg.detect.envelope_window_s * fs);
env = vs_moving_rms(pre.piezo.x, n_win, cfg.detect.envelope_alignment, pre.piezo.segments);
det.envelope = env;
det.envelope_window_samples = n_win;

t = rec.piezo.t_us;
rid = rec.piezo.record_id;
usable = ~isnan(env) & ~pre.piezo.mask.near_edge;
refractory_us = cfg.detect.refractory_s * 1e6;
pre_s = cfg.record.pre_trigger_s;
if isfield(rec.meta, 'pre_trigger_s')
    pre_s = str2double(rec.meta.pre_trigger_s);
end
bg_s = pre_s - cfg.preprocess.bias_exclude_before_trigger_s;

% A crossing inside a filter edge zone (pre.piezo.mask.near_edge) is not
% counted: odd-reflection padding of a noisy run can leave a small
% high-pass transient there. Such crossings are listed in
% det.edge_candidates so they are visible, not silently dropped. Triggered
% records put the impact about 300 ms from the record start, far from it.
run_start = false(numel(t), 1);
run_start(pre.piezo.segments(:, 1)) = true;
near_edge = pre.piezo.mask.near_edge;

onset_idx = [];
edge_idx = [];
thresholds = struct('record_id', {}, 'threshold_v', {}, 'stats', {});
ids = unique(rid(~isnan(rid))).';
for k = 1:numel(ids)
    idx = find(rid == ids(k));
    bg = usable(idx);
    if strcmp(rec.recording_mode, 'triggered') && strcmp(cfg.detect.background_source, 'pre_trigger')
        bg = bg & t(idx) < min(t(idx)) + bg_s * 1e6;
    end
    [thr, stats] = vs_adaptive_threshold(env(idx(bg)), cfg.detect.threshold_mad_multiplier, ...
        cfg.detect.noise_floor_threshold);
    thresholds(k).record_id = ids(k);
    thresholds(k).threshold_v = thr;
    thresholds(k).stats = stats;
    if isnan(thr)
        continue
    end

    above = env(idx) >= thr;
    prev_above = [false; above(1:end-1)];
    prev_above(run_start(idx)) = false;          % a new run has no "previous" sample
    cand = find(above & ~prev_above);
    last = -Inf;
    for c = cand.'
        if t(idx(c)) - last < refractory_us
            continue
        end
        if near_edge(idx(c))
            edge_idx(end+1, 1) = idx(c); %#ok<AGROW>
        else
            onset_idx(end+1, 1) = idx(c); %#ok<AGROW>
        end
        last = t(idx(c));       % an edge crossing also starts a refractory interval
    end
end

det.thresholds = thresholds;
det.onset_idx = onset_idx;
det.onset_t_us = t(onset_idx);
det.record_id = rid(onset_idx);
det.edge_candidates.t_us = t(edge_idx);
det.edge_candidates.record_id = rid(edge_idx);
det.peak_envelope_v = zeros(numel(onset_idx), 1);
peak_span_us = max(refractory_us, n_win * 1e6 / fs);
for j = 1:numel(onset_idx)
    w = rid == det.record_id(j) & t >= det.onset_t_us(j) & t < det.onset_t_us(j) + peak_span_us;
    det.peak_envelope_v(j) = max(env(w));
end

% ---- Optional gyro confirmation (both rules are kept)
det = vs_confirm_swing(det, rec, qc, pre, cfg);
stationary = any(strcmp(vs_session_role(rec.meta), {'reference', 'controlled'}));
det.swing_rule_applied = cfg.detect.swing_confirm_enabled && ~stationary;
if det.swing_rule_applied
    det.accepted = det.swing_confirmed;
else
    det.accepted = true(numel(onset_idx), 1);
end
end
