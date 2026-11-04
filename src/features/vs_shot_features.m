function [shots, spectra] = vs_shot_features(rec, qc, pre, det, cfg)
%VS_SHOT_FEATURES Per-shot impact RMS, pre-impact angular speed and spectrum.
%
%   [shots, spectra] = vs_shot_features(rec, qc, pre, det, cfg)
%
%   One row per detection in det (vs_detect_impacts), including detections
%   the gyro rule rejected, so attempted, accepted and rejected counts can
%   all be reported (proposal, "Data handling and reporting").
%
%   Features (proposal values in cfg, docs/settings_provenance.md):
%     rms_v               RMS of the filtered piezo signal (V at the ADC
%                         pin) over the first features.rms_window_s (100 ms)
%                         after the onset: round(0.1 x measured rate) samples
%                         starting at the onset sample
%     preimpact_peak_dps  peak filtered angular-speed magnitude in the
%                         features.preimpact_window_s (250 ms) before onset
%     spectrum            spectrum.nfft (2048) samples from the onset sample
%                         of cfg.spectrum.signal ('bias_removed' or
%                         'filtered'), Hann-windowed (vs_spectrum), bins
%                         labelled with the measured rate
%
%   Each window has its own flags (vs_window_check codes, prefixed rms_,
%   fft_ or preimpact_). A value is still reported when its window is
%   complete but contaminated; it is NaN only when the window is
%   incomplete. The *_valid columns are true only for accepted detections
%   with a clean window, and only valid values enter CVs and the reference.
%   Pre-impact flags: preimpact_incomplete (IMU data does not cover the
%   window), preimpact_invalid (NaN, clipped, unfiltered sample or gap);
%   preimpact_near_edge is a note only, because a triggered record's 300 ms
%   pre-trigger leaves the 250 ms window starting at the filter edge zone.
%
%   shots is a struct of column vectors (one element per shot); spectra
%   holds freq_hz (bins) and amp (bins x shots, NaN when not computed).
%
%   Tests: tests/unit/test_features.m

fs = qc.piezo.measured_fs_hz;
n = numel(det.onset_idx);
n_rms = round(cfg.features.rms_window_s * fs);
n_fft = cfg.spectrum.nfft;

shots.session_id = repmat({rec.meta.session_id}, n, 1);
shots.shot = (1:n).';
shots.record_id = det.record_id(:);
shots.onset_idx = det.onset_idx(:);
shots.onset_t_us = det.onset_t_us(:);
shots.onset_t_s = (det.onset_t_us(:) - rec.t0_us) / 1e6;
shots.peak_envelope_v = det.peak_envelope_v(:);
shots.swing_evaluated = repmat(det.swing_evaluated, n, 1);
shots.swing_confirmed = det.swing_confirmed(:);
shots.swing_rule_applied = repmat(det.swing_rule_applied, n, 1);
shots.accepted = det.accepted(:);
shots.status = repmat({'accepted'}, n, 1);
shots.status(~shots.accepted) = {'rejected_not_swing_confirmed'};
shots.rms_v = nan(n, 1);
shots.rms_n_samples = repmat(n_rms, n, 1);
shots.rms_flags = repmat({''}, n, 1);
shots.rms_valid = false(n, 1);
shots.preimpact_peak_dps = nan(n, 1);
shots.preimpact_peak_t_us = nan(n, 1);
shots.preimpact_n_samples = zeros(n, 1);
shots.preimpact_flags = repmat({''}, n, 1);
shots.preimpact_valid = false(n, 1);
shots.fft_computed = false(n, 1);
shots.fft_flags = repmat({''}, n, 1);
shots.fft_valid = false(n, 1);
shots.fft_peak_hz = nan(n, 1);

% Per-sample context for the piezo windows
ctx.record_id = rec.piezo.record_id;
ctx.after_gap = qc.piezo.mask.after_gap;
ctx.time_error = qc.piezo.mask.time_error;
ctx.clipped = qc.piezo.mask.clipped;
ctx.envelope = det.envelope;
ctx.envelope_window_samples = det.envelope_window_samples;
ctx.second_event_ratio = cfg.features.second_event_ratio;
ctx_rms = ctx;
ctx_rms.invalid = isnan(pre.piezo.x);
ctx_rms.near_edge = pre.piezo.mask.near_edge;
ctx_fft = ctx;
switch cfg.spectrum.signal
    case 'bias_removed'
        x_fft = pre.piezo.x_biasfree;
        ctx_fft.near_edge = [];
    case 'filtered'
        x_fft = pre.piezo.x;
        ctx_fft.near_edge = pre.piezo.mask.near_edge;
    otherwise
        error('vs_shot_features:spectrumSignal', ...
            'spectrum.signal must be bias_removed or filtered');
end
ctx_fft.invalid = isnan(x_fft);

spectra.freq_hz = (0:n_fft/2).' * fs / n_fft;
spectra.amp = nan(n_fft/2 + 1, n);
spectra.signal = cfg.spectrum.signal;
spectra.fs_hz = fs;

w_speed = vs_angular_speed(pre.gyro_dps);
imu_invalid = qc.imu.mask.nan | qc.imu.mask.gyro_clipped | pre.imu.mask.not_filtered | ...
    qc.imu.mask.after_gap | qc.imu.mask.time_error;

thr_ids = [det.thresholds.record_id];
for j = 1:n
    thr = det.thresholds(thr_ids == shots.record_id(j)).threshold_v;
    ctx_rms.threshold_v = thr;
    ctx_fft.threshold_v = thr;
    i0 = shots.onset_idx(j);

    % ---- Impact RMS
    w = vs_window_check(i0, n_rms, ctx_rms);
    if w.complete
        shots.rms_v(j) = vs_impact_rms(pre.piezo.x(w.idx));
    end
    shots.rms_flags{j} = join_flags('rms_', w.flags);
    shots.rms_valid(j) = shots.accepted(j) && isempty(w.flags) && ~isnan(shots.rms_v(j));

    % ---- Spectrum
    w = vs_window_check(i0, n_fft, ctx_fft);
    if w.complete && ~any(ctx_fft.invalid(w.idx))
        s = vs_spectrum(x_fft(w.idx), fs, cfg.spectrum.hann_form);
        spectra.amp(:, j) = s.amp;
        shots.fft_computed(j) = true;
        shots.fft_peak_hz(j) = s.peak_hz;
    end
    shots.fft_flags{j} = join_flags('fft_', w.flags);
    shots.fft_valid(j) = shots.fft_computed(j) && isempty(w.flags);

    % ---- Pre-impact peak angular speed
    in_rec = find(rec.imu.record_id == shots.record_id(j));
    p = vs_preimpact_peak(rec.imu.t_us(in_rec), w_speed(in_rec), shots.onset_t_us(j), ...
        cfg.features.preimpact_window_s, qc.imu.measured_fs_hz, imu_invalid(in_rec));
    shots.preimpact_peak_dps(j) = p.peak_dps;
    shots.preimpact_peak_t_us(j) = p.peak_t_us;
    shots.preimpact_n_samples(j) = p.n_samples;
    f = {};
    if ~p.complete
        f{end+1} = 'incomplete'; %#ok<AGROW>
    end
    if p.touches_invalid
        f{end+1} = 'invalid'; %#ok<AGROW>
    end
    valid = shots.accepted(j) && isempty(f) && ~isnan(p.peak_dps);
    t0 = shots.onset_t_us(j) - cfg.features.preimpact_window_s * 1e6;
    sel = in_rec(rec.imu.t_us(in_rec) >= t0 & rec.imu.t_us(in_rec) < shots.onset_t_us(j));
    if any(pre.imu.mask.near_edge(sel))
        f{end+1} = 'near_edge'; %#ok<AGROW>
    end
    shots.preimpact_flags{j} = join_flags('preimpact_', f);
    shots.preimpact_valid(j) = valid;
end
end

function s = join_flags(prefix, flags)
s = '';
for i = 1:numel(flags)
    if i > 1
        s = [s ';']; %#ok<AGROW>
    end
    s = [s prefix flags{i}]; %#ok<AGROW>
end
end
