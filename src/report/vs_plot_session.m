function file = vs_plot_session(res, cfg, out_dir)
%VS_PLOT_SESSION Session figure: signals, detections, shots and spectra.
%
%   file = vs_plot_session(res, cfg, out_dir)
%
%   Writes <out_dir>/<session_id>.png with four panels, as the proposal's
%   laptop display describes ("detected impacts, relative intensity per
%   shot, filtered vibration and angular-motion plots, the impact
%   spectrum"):
%     1. filtered piezo signal, its 5 ms RMS envelope, the threshold and
%        each detection (filled = accepted, open = rejected)
%     2. filtered angular-speed magnitude with each 250 ms pre-impact
%        window and its peak
%     3. intensity index per shot (RMS when there is no reference); only
%        valid values are drawn, invalid shots are marked on the axis
%     4. spectra of shots with a valid window, up to spectrum.display_max_hz
%   Synthetic sessions carry "SYNTHETIC TEST DATA - not a measurement" in
%   the title. The figure is created invisibly and closed after saving.
%
%   Tests: tests/integration/test_pipeline.m

s = res.shots;
rec = res.rec;
sid = res.meta.session_id;
banner = sid;
if res.synthetic
    banner = sprintf('SYNTHETIC TEST DATA - not a measurement - %s', sid);
end

fig = figure('Visible', 'off', 'Position', [100 100 1100 850]);
closer = onCleanup(@() close(fig));

% ---- 1. Filtered piezo and detections
subplot(4, 1, 1);
hold on
ids = unique(rec.piezo.record_id(~isnan(rec.piezo.record_id))).';
for k = ids
    i = rec.piezo.record_id == k;
    plot(rec.piezo.t_s(i), res.pre.piezo.x(i), 'Color', [0.6 0.6 0.6]);
    plot(rec.piezo.t_s(i), res.det.envelope(i), 'b');
    th = res.det.thresholds([res.det.thresholds.record_id] == k).threshold_v;
    t_rec = rec.piezo.t_s(i);
    plot([min(t_rec) max(t_rec)], [th th], 'r--');
end
y = max([res.det.envelope; 1e-6]);
if any(s.accepted)
    plot(s.onset_t_s(s.accepted), y * ones(sum(s.accepted), 1), 'kv', 'MarkerFaceColor', 'k');
end
if any(~s.accepted)
    plot(s.onset_t_s(~s.accepted), y * ones(sum(~s.accepted), 1), 'kv');
end
hold off
ylabel('piezo (V)');
title(sprintf('%s: filtered piezo (grey), 5 ms RMS envelope (blue), threshold (red)', banner), ...
    'Interpreter', 'none');

% ---- 2. Angular speed and pre-impact windows
subplot(4, 1, 2);
hold on
w = vs_angular_speed(res.pre.gyro_dps);
ids = unique(rec.imu.record_id(~isnan(rec.imu.record_id))).';
for k = ids
    i = rec.imu.record_id == k;
    plot(rec.imu.t_s(i), w(i), 'Color', [0 0.5 0]);
end
win = cfg.features.preimpact_window_s;
top = max([w; 1]);
for j = 1:numel(s.shot)
    plot(s.onset_t_s(j) - [win 0], [top top] * 1.02, 'k-', 'LineWidth', 2);
    if ~isnan(s.preimpact_peak_t_us(j))
        plot((s.preimpact_peak_t_us(j) - rec.t0_us) / 1e6, s.preimpact_peak_dps(j), 'ko');
    end
end
hold off
ylabel('angular speed (deg/s)');
title('Filtered angular-speed magnitude; bars = 250 ms pre-impact windows, circles = peaks');

% ---- 3. Intensity index (or RMS) per shot
subplot(4, 1, 3);
use_index = isfield(s, 'intensity_index') && any(~isnan(s.intensity_index));
if use_index
    v = s.intensity_index;
    label = 'intensity index I';
else
    v = s.rms_v;
    label = 'RMS (V)';
end
ok = s.rms_valid & ~isnan(v);
hold on
if any(ok)
    bar(s.shot(ok), v(ok), 0.6);
end
if any(~ok)
    plot(s.shot(~ok), zeros(sum(~ok), 1), 'rx', 'MarkerSize', 10);
end
if use_index
    plot([0.5 max([s.shot; 1]) + 0.5], [100 100], 'k:');
end
hold off
xlim([0.5 max([s.shot; 1]) + 0.5]);
xlabel('shot');
ylabel(label);
title(sprintf('%s per shot (red x = not valid: rejected or flagged window)', label));

% ---- 4. Spectra
subplot(4, 1, 4);
f = res.spectra.freq_hz;
keep = f <= cfg.spectrum.display_max_hz;
k = find(s.fft_valid);
if ~isempty(k)
    plot(f(keep), res.spectra.amp(keep, k));
else
    text(0.5, 0.5, 'No valid spectrum window', 'Units', 'normalized', ...
        'HorizontalAlignment', 'center');
end
xlabel('frequency (Hz)');
ylabel('amplitude (V)');
title(sprintf(['2048-sample Hann FFT from onset (%s signal, bins %.2f Hz at the measured ' ...
    'rate) - exploratory only'], strrep(res.spectra.signal, '_', ' '), f(2)));

file = fullfile(out_dir, [sid '.png']);
print(fig, file, '-dpng', '-r90');
end
