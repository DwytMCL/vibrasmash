function env = vs_check_environment()
%VS_CHECK_ENVIRONMENT Report the platform and every external dependency.
%
%   env = vs_check_environment()
%
%   Never throws. env.ok is true only when every requirement is met:
%     - MATLAB R2019b (9.7) or newer
%     - Signal Processing Toolbox installed and licensed (butter, filtfilt, hann)
%   GNU Octave 8.4+ with the signal package is also accepted, since the
%   check costs nothing extra, but MATLAB is the supported platform.
%
%   Tests: tests/unit/test_environment.m

env.is_octave = exist('OCTAVE_VERSION', 'builtin') ~= 0;
env.platform = computer();
env.is_windows = ispc();

if env.is_octave
    env.product = 'GNU Octave';
    env.version = OCTAVE_VERSION();
    env.min_version = '8.4.0';
    env.version_ok = compare_versions(env.version, env.min_version, '>=');
else
    env.product = 'MATLAB';
    env.version = version();
    env.min_version = '9.7 (R2019b)';
    env.version_ok = ~verLessThan('matlab', '9.7');
end

% Signal processing functions: Signal Processing Toolbox in MATLAB,
% the 'signal' package in Octave.
env.signal_name = '';
env.signal_version = '';
env.signal_installed = false;
env.signal_licensed = false;
if env.is_octave
    env.signal_name = 'Octave signal package';
    try
        pkg('load', 'signal');
        env.signal_installed = true;
        env.signal_licensed = true;
        [~, info] = pkg('list');
        for i = 1:numel(info)
            if strcmp(info{i}.name, 'signal')
                env.signal_version = info{i}.version;
            end
        end
    catch
    end
else
    env.signal_name = 'Signal Processing Toolbox';
    v = ver('signal');
    env.signal_installed = ~isempty(v);
    if env.signal_installed
        env.signal_version = v(1).Version;
    end
    env.signal_licensed = license('test', 'Signal_Toolbox') == 1;
end

% Functions the pipeline calls. butter, filtfilt and hann come from the
% Signal Processing Toolbox; the rest are core MATLAB.
env.required_functions = {'butter', 'filtfilt', 'hann', 'fft', 'median', ...
                          'std', 'textscan', 'fopen', 'print'};
env.missing_functions = {};
for i = 1:numel(env.required_functions)
    if ~any(exist(env.required_functions{i}) == [2 3 5 6]) %#ok<EXIST>
        env.missing_functions{end+1} = env.required_functions{i};
    end
end

env.ok = env.version_ok && env.signal_installed && env.signal_licensed ...
    && isempty(env.missing_functions);
end
