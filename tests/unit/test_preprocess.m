function tests = test_preprocess
%TEST_PREPROCESS Unit tests for the preprocessing module (src/preprocess).
%   Inputs are synthetic sines and synthetic fixtures; nothing here is a
%   measurement.
tests = functiontests(localfunctions);
end

function setupOnce(~)
vs_setup();
end

% ---- Filter design -------------------------------------------------------

function testDesignsUseProposalOrdersAndCutoffs(~)
F = vs_design_filters(default_config(), 20000, 200);
assert(numel(F.piezo_hp.b) == 5 && numel(F.piezo_hp.a) == 5, '4th order = 5 coefficients');
assert(numel(F.piezo_lp.b) == 5 && numel(F.gyro_lp.b) == 5);
assert(F.piezo_hp.cutoff_hz == 80 && strcmp(F.piezo_hp.type, 'high'));
assert(F.piezo_lp.cutoff_hz == 2000 && strcmp(F.piezo_lp.type, 'low'));
assert(F.gyro_lp.cutoff_hz == 20 && F.gyro_lp.fs_hz == 200);
end

function testSinglePassResponseIsMinus3dBAtCutoff(~)
F = vs_design_filters(default_config(), 20000, 200);
assert(abs(gain(F.piezo_hp, 80) - 1/sqrt(2)) < 1e-6);
assert(abs(gain(F.piezo_lp, 2000) - 1/sqrt(2)) < 1e-6);
assert(abs(gain(F.gyro_lp, 20) - 1/sqrt(2)) < 1e-6);
end

function testDesignUsesMeasuredRate(~)
% At a measured 19 kHz the 2 kHz cutoff must still be at 2 kHz.
F = vs_design_filters(default_config(), 19000, 200);
assert(F.piezo_lp.fs_hz == 19000);
assert(abs(gain(F.piezo_lp, 2000) - 1/sqrt(2)) < 1e-6);
end

function testCutoffAboveNyquistIsAnError(~)
threw = false;
try
    vs_design_filters(default_config(), 3000, 200);   % 2 kHz LP needs fs > 4 kHz
catch err
    threw = strcmp(err.identifier, 'vs_design_filters:nyquist');
end
assert(threw);
end

% ---- Zero-phase padded filtering -----------------------------------------

function testZeroPhaseResponseIsMinus6dBAtEachCutoff(~)
F = vs_design_filters(default_config(), 20000, 200);
assert(abs(sine_gain(F.piezo_hp, 80, 20000) - 0.5) < 0.005);
assert(abs(sine_gain(F.piezo_lp, 2000, 20000) - 0.5) < 0.005);
assert(abs(sine_gain(F.gyro_lp, 20, 200) - 0.5) < 0.005);
end

function testPassbandIsKeptAndStopbandRemoved(~)
F = vs_design_filters(default_config(), 20000, 200);
chain = [F.piezo_hp F.piezo_lp];
assert(abs(sine_gain(chain, 600, 20000) - 1) < 0.01, '600 Hz is in the passband');
assert(sine_gain(chain, 20, 20000) < 1e-3, '20 Hz is two octaves below the high-pass');
assert(sine_gain(chain, 6000, 20000) < 1e-3, '6 kHz is well above the low-pass');
end

function testFilteringAddsNoPhaseShift(~)
F = vs_design_filters(default_config(), 20000, 200);
fs = 20000;
t = (0:fs-1).' / fs;
x = sin(2 * pi * 600 * t);
y = vs_filter_padded(x, [F.piezo_hp F.piezo_lp], 1000);
mid = 5000:15000;
assert(max(abs(y(mid) - x(mid))) < 0.01, 'Output must line up with the input sample for sample');
end

function testPaddingRemovesEdgeTransient(~)
% Without padding, the 80 Hz high-pass rings at the record edges; the
% explicit odd-reflection padding keeps the first 20 ms accurate.
F = vs_design_filters(default_config(), 20000, 200);
fs = 20000;
t = (0:round(0.3 * fs) - 1).' / fs;
x = 0.2 + sin(2 * pi * 600 * t);           % offset plus a passband tone
expected = sin(2 * pi * 600 * t);
y = vs_filter_padded(x, [F.piezo_hp F.piezo_lp], round(0.05 * fs));
unpadded = filtfilt(F.piezo_lp.b, F.piezo_lp.a, filtfilt(F.piezo_hp.b, F.piezo_hp.a, x));
first = 1:round(0.02 * fs);
assert(max(abs(y(first) - expected(first))) < 0.01);
assert(max(abs(unpadded(first) - expected(first))) > 0.05, ...
    'Sanity check: plain filtfilt does show the edge transient');
end

function testSegmentsAreFilteredIndependently(~)
% A burst that ends at a gap must not leak into the next segment.
F = vs_design_filters(default_config(), 20000, 200);
x = [sin(2 * pi * 600 * (0:3999).' / 20000); zeros(4000, 1)];
y = vs_filter_padded(x, [F.piezo_hp F.piezo_lp], 1000, [1 4000; 4001 8000]);
assert(all(y(4001:end) == 0));
yc = vs_filter_padded(x, [F.piezo_hp F.piezo_lp], 1000);
assert(max(abs(yc(4001:4100))) > 0.01, 'Sanity check: one segment does leak');
end

function testNanSamplesStayNanAndDoNotSpread(~)
F = vs_design_filters(default_config(), 20000, 200);
x = sin(2 * pi * 600 * (0:7999).' / 20000);
x(4000) = NaN;
seg = vs_contiguous_segments(zeros(8000, 1), false(8000, 1), isnan(x));
assert(isequal(seg, [1 3999; 4001 8000]));
y = vs_filter_padded(x, [F.piezo_hp F.piezo_lp], 1000, seg);
assert(isnan(y(4000)) && sum(isnan(y)) == 1);
end

function testRunsTooShortToFilterAreLeftNan(~)
F = vs_design_filters(default_config(), 20000, 200);
x = randn(100, 1);
[y, info] = vs_filter_padded(x, F.piezo_hp, 10, [1 5; 6 100]);
assert(all(isnan(y(1:5))) && ~any(isnan(y(6:100))));
assert(isequal(info.too_short, 1));
end

function testSegmentsSplitAtRecordsAndBreaks(~)
rid = [1 1 1 1 2 2 2 2].';
brk = false(8, 1); brk(3) = true;
seg = vs_contiguous_segments(rid, brk, false(8, 1));
assert(isequal(seg, [1 2; 3 4; 5 8]));
end

% ---- Bias removal --------------------------------------------------------

function testContinuousBiasIsRecordMedian(~)
[pre, rec, ~, c] = run_fixture(struct('name', 'biascont')); %#ok<ASGLU>
assert(numel(pre.piezo.bias) == 1);
assert(strcmp(pre.piezo.bias.method, 'median_record'));
assert(abs(pre.piezo.bias.bias_v - median(rec.piezo.v)) < 1e-12);
assert(abs(pre.piezo.bias.bias_v - 1.650) < 0.002);
end

function testTriggeredBiasUsesPreTriggerSamplesPerRecord(~)
[info, c] = generate(struct('name', 'biastrig', 'recording_mode', 'triggered')); %#ok<ASGLU>
% Shift record 2 by +100 ADC counts to check each record gets its own bias.
T = vs_read_csv_table(info.files.piezo);
X = T.data;
X(X(:, 3) == 2, 2) = X(X(:, 3) == 2, 2) + 100;
write_csv(info.files.piezo, T.header, X);
cfg = default_config();
rec = vs_read_recording(info.folder);
[x, bias] = vs_remove_bias(rec, cfg);
assert(numel(bias) == 3 && all(strcmp({bias.method}, 'median_pre_trigger')));
assert(abs((bias(2).bias_v - bias(1).bias_v) - 100 * 3.3 / 4095) < 0.002);
% 300 ms pre-trigger minus 20 ms excluded = 280 ms = 5600 samples
assert(all([bias.n_samples_used] == 5600));
pre_idx = rec.piezo.record_id == 2 & rec.piezo.t_us < min(rec.piezo.t_us(rec.piezo.record_id == 2)) + 280000;
assert(abs(median(x(pre_idx))) < 1e-12);
end

% ---- Whole preprocessing step --------------------------------------------

function testPreprocessKeepsSamplesAndUsesMeasuredRates(~)
[pre, rec, qc, c] = run_fixture(struct('name', 'keep', 'piezo_fs_hz', 19000)); %#ok<ASGLU>
assert(numel(pre.piezo.x) == numel(rec.piezo.t_us));
assert(isequal(size(pre.gyro_dps), size(rec.imu.gyro_dps)));
assert(pre.filters.piezo_lp.fs_hz == qc.piezo.measured_fs_hz);
assert(pre.filters.gyro_lp.fs_hz == qc.imu.measured_fs_hz);
end

function testPlantedBurstSurvivesFiltering(~)
[pre, rec, ~, c] = run_fixture(struct('name', 'burst')); %#ok<ASGLU>
spec = make_synthetic_fixture();
onset = spec.clock_start_us + spec.events(1).t_s * 1e6;
w = rec.piezo.t_us >= onset & rec.piezo.t_us < onset + 5000;
peak_v = max(abs(pre.piezo.x(w)));
expected_v = spec.events(1).piezo_amp_mv / 1000;
assert(abs(peak_v - expected_v) / expected_v < 0.10, 'Peak %.4f V, planted %.4f V', peak_v, expected_v);
before = rec.piezo.t_us >= onset - 50000 & rec.piezo.t_us < onset - 5000;
assert(max(abs(pre.piezo.x(before))) < 0.01, 'No energy should appear well before the onset');
end

function testFilteredGyroKeepsPlantedSwingPeak(~)
[pre, rec, ~, c] = run_fixture(struct('name', 'gyro')); %#ok<ASGLU>
spec = make_synthetic_fixture();
onset = spec.clock_start_us + spec.events(1).t_s * 1e6;
w = rec.imu.t_us >= onset - 250000 & rec.imu.t_us < onset;
peak = max(sqrt(sum(pre.gyro_dps(w, :).^2, 2)));
assert(abs(peak - spec.events(1).gyro_peak_dps) < 0.03 * spec.events(1).gyro_peak_dps);
end

function testGapSplitsFilteringAndEdgesAreMarked(~)
[pre, rec, ~, c] = run_fixture(struct('name', 'gap', 'piezo_drop_s', [2.5 2.6])); %#ok<ASGLU>
assert(size(pre.piezo.segments, 1) == 2);
after = find(rec.piezo.t_us >= 1000000 + 2.6e6, 1);
assert(pre.piezo.segments(2, 1) == after);
assert(pre.piezo.mask.near_edge(after) && pre.piezo.mask.near_edge(after - 1));
assert(~pre.piezo.mask.near_edge(after + pre.piezo.pad_n));
assert(~any(pre.piezo.mask.not_filtered));
end

% ---- Helpers ------------------------------------------------------------

function g = gain(f, freq)
% Single-pass magnitude response |H(e^jw)| from the coefficients.
z = exp(-1i * 2 * pi * freq / f.fs_hz);
g = abs(polyval(fliplr(f.b), z) / polyval(fliplr(f.a), z));
end

function g = sine_gain(filters, freq, fs)
% RMS gain of padded zero-phase filtering for a 4 s sine, away from the edges.
t = (0:4*fs-1).' / fs;
x = sin(2 * pi * freq * t);
y = vs_filter_padded(x, filters, round(0.05 * fs));
mid = round(fs):round(3*fs);
g = sqrt(mean(y(mid).^2)) / sqrt(mean(x(mid).^2));
end

function [pre, rec, qc, cleanup] = run_fixture(spec)
[info, cleanup] = generate(spec);
cfg = default_config();
rec = vs_read_recording(info.folder);
qc = vs_validate_recording(rec, cfg);
pre = vs_preprocess(rec, qc, cfg);
end

function [info, cleanup] = generate(spec)
spec.out_dir = tempname();
mkdir(spec.out_dir);
cleanup = onCleanup(@() rmdir(spec.out_dir, 's'));
info = make_synthetic_fixture(spec);
end

function write_csv(file, header, X)
fid = fopen(file, 'w');
fprintf(fid, '%s\n', strjoin(header, ','));
fmt = [strjoin(repmat({'%.10g'}, 1, size(X, 2)), ',') '\n'];
fprintf(fid, fmt, X.');
fclose(fid);
end
