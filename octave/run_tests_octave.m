function ok = run_tests_octave(subset)
%RUN_TESTS_OCTAVE Octave part of run_tests.
%   For each tests/**/test_*.m file: calls setupOnce, every test* local
%   function, then teardownOnce, passing one OctaveTestCase (for TestData),
%   and prints passed / FAILED for each test and a total.

root = vs_setup();
confirm_recursive_rmdir(false);
folder = fullfile(root, subset);
files = find_tests(folder);
printf('VibraSmash test run: GNU Octave %s on %s\n', OCTAVE_VERSION, computer());
np = 0;
nt = 0;
for k = 1:numel(files)
    [d, f] = fileparts(files{k});
    addpath(d);
    hs = feval(f);
    names = cellfun(@func2str, hs, 'UniformOutput', false);
    tc = OctaveTestCase();
    printf('Running %s\n', f);
    i_setup = find(strcmp(names, 'setupOnce'));
    setup_ok = true;
    if ~isempty(i_setup)
        try
            hs{i_setup}(tc);
        catch e
            setup_ok = false;
            printf('  setupOnce FAILED: %s\n', e.message);
        end
    end
    for i = 1:numel(hs)
        if isempty(regexp(names{i}, '^test', 'once'))
            continue
        end
        nt = nt + 1;
        if ~setup_ok
            printf('  FAILED %s/%s (setupOnce failed)\n', f, names{i});
            continue
        end
        try
            hs{i}(tc);
            np = np + 1;
            printf('  passed %s/%s\n', f, names{i});
        catch e
            printf('  FAILED %s/%s: %s\n', f, names{i}, e.message);
        end
    end
    i_td = find(strcmp(names, 'teardownOnce'));
    if ~isempty(i_td)
        try
            hs{i_td}(tc);
        catch e
            printf('  teardownOnce failed: %s\n', e.message);
        end
    end
end
ok = nt > 0 && np == nt;
printf('\nTotal: %d / %d tests passed\n', np, nt);
end

function files = find_tests(folder)
files = {};
d = dir(fullfile(folder, 'test_*.m'));
for i = 1:numel(d)
    files{end+1} = fullfile(folder, d(i).name); %#ok<AGROW>
end
sub = dir(folder);
for i = 1:numel(sub)
    if sub(i).isdir && sub(i).name(1) ~= '.'
        files = [files find_tests(fullfile(folder, sub(i).name))]; %#ok<AGROW>
    end
end
end
