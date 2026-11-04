function tests = test_environment
%TEST_ENVIRONMENT Unit tests for src/util/vs_check_environment.m.
tests = functiontests(localfunctions);
end

function setupOnce(~)
vs_setup();
end

function testReportHasExpectedFields(~)
env = vs_check_environment();
fields = {'ok', 'product', 'version', 'version_ok', 'signal_installed', ...
          'signal_licensed', 'missing_functions'};
for i = 1:numel(fields)
    assert(isfield(env, fields{i}), 'Missing field %s', fields{i});
end
assert(islogical(env.ok));
end

function testEnvironmentMeetsRequirements(~)
env = vs_check_environment();
assert(env.version_ok, '%s %s is older than %s', env.product, env.version, env.min_version);
assert(env.signal_installed, '%s is not installed', env.signal_name);
assert(env.signal_licensed, '%s is installed but not licensed', env.signal_name);
assert(isempty(env.missing_functions), 'Missing functions: %s', ...
    strjoin(env.missing_functions, ', '));
end
