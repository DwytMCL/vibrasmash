function ok = run_tests(subset)
%RUN_TESTS Run the VibraSmash test suite in MATLAB or GNU Octave.
%
%   ok = run_tests()                    runs every test under tests/
%   ok = run_tests('tests/integration') runs one folder
%
%   Returns true only if at least one test ran and every test passed.
%   MATLAB uses its unit test framework (run_tests_matlab.m). Octave has no
%   matlab.unittest, so it uses octave/run_tests_octave.m, which calls the
%   same test files' setupOnce, test* and teardownOnce functions.
%
%   MATLAB, from Command Prompt or PowerShell (exit code 0 = all passed):
%     matlab -batch "cd('C:/work/vibrasmash'); assert(run_tests())"
%   Octave (needs the signal package: pkg install -forge signal):
%     cd /path/to/vibrasmash; run_tests

if nargin < 1
    subset = 'tests';
end
if exist('OCTAVE_VERSION', 'builtin')
    root = fileparts(mfilename('fullpath'));
    addpath(fullfile(root, 'octave'));
    ok = run_tests_octave(subset);
else
    ok = run_tests_matlab(subset);
end
end
