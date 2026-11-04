function debug_pipeline()
%DEBUG_PIPELINE Locate a MATLAB error that stops tests/integration/test_pipeline.m.
%
%     vs_setup; debug_pipeline
%
%   Runs the pipeline outside the test framework, printing every step as it
%   starts. If MATLAB stops the whole command, the last line printed shows
%   where. Steps are ordered to separate graphics from everything else:
%     A  one session, no reference, no plots, before any figure exists
%     B  the full demo without plots
%     C  step A again
%     D  the full demo with plots
%     E  step A again, after figures were made (the case that stopped the
%        integration test)
%   Errors MATLAB can catch are printed with their stack and the next step
%   runs. All data is SYNTHETIC; nothing here is a measurement.

root = fileparts(fileparts(mfilename('fullpath')));
out = tempname();
mkdir(out);
fprintf('debug_pipeline: %s, project %s\n', version(), root);
fprintf('Temporary folder: %s\n', out);

spec = make_synthetic_fixture();
spec.name = 'debug_single';
spec.out_dir = out;
spec.synthetic_role = 'controlled';
spec.meta_extra = struct('condition', 'middle');
single = make_synthetic_fixture(spec);
cfg = default_config();
cfg.detect.noise_floor_threshold = 0.005;       % TEST value, synthetic noise only
cfg.detect.swing_confirm_threshold_dps = 60;    % TEST value, synthetic noise only

step('A: one session, no reference, no plots', @() single_run('A'));
step('B: demo without plots', @() demo_synthetic(out, false, true));
step('C: one session again', @() single_run('C'));
step('D: demo with plots', @() demo_synthetic(out, true, true));
step('E: one session after plots', @() single_run('E'));
step('F: run without sessions (an error is expected)', @() nosessions());
fprintf('\ndebug_pipeline finished. Every step that printed OK worked.\n');

    function single_run(label)
        opts.sessions = {single.folder};
        opts.cfg = cfg;
        opts.out_root = out;
        opts.label = ['debug_' label];
        opts.plots = false;
        opts.verbose = true;
        r = run_vibrasmash(opts);
        fprintf('  warnings: %s\n', strjoin(r.warnings, ' | '));
    end
end

function nosessions()
try
    run_vibrasmash(struct('sessions', {{}}));
catch err
    if ~strcmp(err.identifier, 'run_vibrasmash:noSessions')
        rethrow(err);
    end
    fprintf('  got the expected error run_vibrasmash:noSessions\n');
end
end

function step(name, fn)
fprintf('\n--- %s\n', name);
try
    fn();
    fprintf('  OK: %s\n', name);
catch err
    fprintf('  ERROR in step "%s": %s (identifier "%s")\n', name, err.message, err.identifier);
    for k = 1:numel(err.stack)
        fprintf('    at %s (line %d) in %s\n', err.stack(k).name, err.stack(k).line, ...
            err.stack(k).file);
    end
end
end
