function ok = run_tests_matlab(subset)
%RUN_TESTS_MATLAB MATLAB part of run_tests (MATLAB unit test framework).
%   Called by run_tests; kept in its own file so Octave never runs it.
%
%   ok = run_tests()                    runs every test under tests/
%   ok = run_tests('tests/integration') runs one folder
%
%   Returns true only if at least one test ran and every test passed.
%
%   Each test file runs on its own. If MATLAB aborts a whole file with an
%   error the framework cannot record (for example an internal error such
%   as "invalid vector subscript"), the full error report is printed, that
%   file's tests are re-run one at a time to find the test that causes it,
%   and the run continues with the next file. The summary at the end always
%   lists every test as passed, FAILED, incomplete or CRASHED.
%
%   From Command Prompt or PowerShell (exit code 0 = all passed):
%     matlab -batch "cd('C:/work/vibrasmash'); assert(run_tests())"

root = vs_setup();

folder = fullfile(root, subset);
suite = matlab.unittest.TestSuite.fromFolder(folder, 'IncludingSubfolders', true);
fprintf('VibraSmash test run: MATLAB %s on %s\n', version(), computer());

% MATLAB R2026b aborted with "invalid vector subscript" while its default
% text output plugin printed the test_pipeline report, even though every
% test had passed. A runner with no plugins avoids that; this function
% prints its own per-file progress and summary instead.
runner = matlab.unittest.TestRunner.withNoPlugins();
names = {};
status = {};
parent_of = {suite.TestParentName};
parents = unique(parent_of, 'stable');
% In R2026b, running any test file after test_pipeline in the same session
% aborted MATLAB ("invalid vector subscript"); each passes on its own. Run
% the end-to-end pipeline file last.
last = strcmp(parents, 'test_pipeline');
parents = [parents(~last), parents(last)];
for p = 1:numel(parents)
    group = suite(strcmp(parent_of, parents{p}));
    fprintf('Running %s (%d tests)\n', parents{p}, numel(group));
    try
        results = runner.run(group);
        [names, status] = record(names, status, results);
    catch err
        fprintf('\n*** %s stopped with an error the test framework did not record:\n', parents{p});
        print_report(err);
        fprintf('*** Re-running the %d tests in %s one at a time.\n', numel(group), parents{p});
        for j = 1:numel(group)
            try
                r = runner.run(group(j));
                [names, status] = record(names, status, r);
            catch err2
                fprintf('\n*** CRASHED: %s\n', group(j).Name);
                print_report(err2);
                names{end+1} = group(j).Name; %#ok<AGROW>
                status{end+1} = 'CRASHED'; %#ok<AGROW>
            end
        end
    end
end

fprintf('\n%-60s %s\n', 'Test', 'Result');
for i = 1:numel(names)
    fprintf('%-60s %s\n', names{i}, status{i});
end
n_pass = sum(strcmp(status, 'passed'));
n_total = numel(names);
ok = n_total > 0 && n_pass == n_total;
fprintf('\nTotal: %d / %d tests passed\n', n_pass, n_total);
if any(strcmp(status, 'CRASHED'))
    fprintf('Some tests CRASHED. Please send the whole output, including the error reports.\n');
end
if n_total == 0
    fprintf('No tests found in %s\n', folder);
end
end

function [names, status] = record(names, status, results)
for i = 1:numel(results)
    names{end+1} = results(i).Name; %#ok<AGROW>
    if results(i).Passed
        status{end+1} = 'passed'; %#ok<AGROW>
    elseif results(i).Failed
        status{end+1} = 'FAILED'; %#ok<AGROW>
    else
        status{end+1} = 'incomplete'; %#ok<AGROW>
    end
end
end

function print_report(err)
try
    fprintf('%s\n', getReport(err, 'extended', 'hyperlinks', 'off'));
catch
    fprintf('%s: %s\n', err.identifier, err.message);
end
for k = 1:numel(err.stack)
    fprintf('  at %s (line %d) in %s\n', err.stack(k).name, err.stack(k).line, err.stack(k).file);
end
end
