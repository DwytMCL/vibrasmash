function ok = smoke_test()
%SMOKE_TEST Check that this computer can run the VibraSmash pipeline.
%
%   ok = smoke_test()
%
%   Run once before anything else. In MATLAB, with the vibrasmash folder as
%   the current folder:
%     addpath scripts; smoke_test
%
%   The signals below are tiny synthetic test inputs used only to exercise
%   the functions. Nothing here is a VibraSmash measurement.

root = fileparts(fileparts(mfilename('fullpath')));
addpath(root);
results = cell(0, 3);
fprintf('VibraSmash smoke test\n');

% 1. Platform and Signal Processing Toolbox
try
    vs_setup();
    env = vs_check_environment();
    results = record(results, 'platform version', env.version_ok, ...
        sprintf('%s %s (need >= %s)', env.product, env.version, env.min_version));
    results = record(results, 'signal toolbox installed', env.signal_installed, ...
        sprintf('%s %s', env.signal_name, env.signal_version));
    results = record(results, 'signal toolbox licensed', env.signal_licensed, '');
    results = record(results, 'required functions', isempty(env.missing_functions), ...
        strjoin(env.missing_functions, ', '));
catch err
    results = record(results, 'setup', false, err.message);
end

% 2. Butterworth design + zero-phase filtering on a synthetic sine
try
    fs = 20000;
    t = (0:fs-1).' / fs;
    x = sin(2*pi*500*t);
    [b, a] = butter(4, 2000 / (fs/2));
    y = filtfilt(b, a, x);
    mid = 5000:15000;
    gain = sqrt(mean(y(mid).^2)) / sqrt(mean(x(mid).^2));
    results = record(results, 'butter + filtfilt', abs(gain - 1) < 0.01, ...
        sprintf('500 Hz passband gain %.4f', gain));
catch err
    results = record(results, 'butter + filtfilt', false, err.message);
end

% 3. Hann-windowed FFT bin labelling on a synthetic sine
try
    fs = 20000; n = 2048;
    f0 = 100 * fs / n;               % exactly on bin 100 (976.5625 Hz)
    x = sin(2*pi*f0*(0:n-1).' / fs);
    X = abs(fft(x .* hann(n, 'periodic')));
    [~, k] = max(X(1:n/2+1));
    f_peak = (k - 1) * fs / n;
    results = record(results, 'hann + fft', abs(f_peak - f0) < 1e-9, ...
        sprintf('peak at %.4f Hz, expected %.4f Hz', f_peak, f0));
catch err
    results = record(results, 'hann + fft', false, err.message);
end

% 4. CSV round trip in a temporary folder
try
    tmp = [tempname() '.csv'];
    fid = fopen(tmp, 'w');
    fprintf(fid, 't_us,adc_raw\n0,2048\n50,2050\n');
    fclose(fid);
    fid = fopen(tmp, 'r');
    hdr = fgetl(fid);
    C = textscan(fid, '%f %f', 'Delimiter', ',');
    fclose(fid);
    delete(tmp);
    passed = strcmp(hdr, 't_us,adc_raw') && isequal([C{:}], [0 2048; 50 2050]);
    results = record(results, 'csv read/write', passed, '');
catch err
    results = record(results, 'csv read/write', false, err.message);
end

% 5. Save a figure to PNG without showing a window
try
    h = figure('Visible', 'off');
    plot([0 1], [0 1]);
    xlabel('Time (s)'); ylabel('Amplitude (V)');
    png = [tempname() '.png'];
    print(h, png, '-dpng', '-r72');
    close(h);
    info = dir(png);
    passed = ~isempty(info) && info.bytes > 0;
    if passed
        delete(png);
    end
    results = record(results, 'plot to png', passed, '');
catch err
    results = record(results, 'plot to png', false, err.message);
end

n_fail = sum(~[results{:,2}]);
ok = n_fail == 0;
if ok
    fprintf('Smoke test PASSED (%d checks)\n', size(results, 1));
else
    fprintf('Smoke test FAILED (%d of %d checks failed)\n', n_fail, size(results, 1));
end
end

function results = record(results, name, passed, detail)
results(end+1, :) = {name, passed, detail};
if passed
    fprintf('  PASS  %s  %s\n', name, detail);
else
    fprintf('  FAIL  %s  %s\n', name, detail);
end
end
