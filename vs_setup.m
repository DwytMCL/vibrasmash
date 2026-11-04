function root = vs_setup()
%VS_SETUP Add the VibraSmash folders to the MATLAB path.
%
%   root = vs_setup()
%
%   Safe to call more than once. Returns the project root folder. Does not
%   check toolboxes; run scripts/smoke_test.m or vs_check_environment for that.

root = fileparts(mfilename('fullpath'));
% Change the path only once per session: if this project's src folder is
% already on the path, leave it alone.
already = any(strcmp(strsplit(path, pathsep), fullfile(root, 'src', 'util')));
if ~already
addpath(root);
addpath(fullfile(root, 'config'));
addpath(genpath(fullfile(root, 'src')));
addpath(fullfile(root, 'scripts'));
end

% Octave keeps butter/filtfilt in the separately loaded 'signal' package.
if exist('OCTAVE_VERSION', 'builtin')
    pkg('load', 'signal');
end
end
