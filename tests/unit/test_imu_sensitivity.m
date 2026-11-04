function tests = test_imu_sensitivity
%TEST_IMU_SENSITIVITY Unit tests for src/util/vs_imu_sensitivity.m.
tests = functiontests(localfunctions);
end

function setupOnce(~)
vs_setup();
end

function testProposalRangesMatchDatasheet(~)
% Proposal ranges: +/-2000 deg/s and +/-16 g. Datasheet: 16.4 LSB/(deg/s), 2048 LSB/g.
[g, a] = vs_imu_sensitivity(2000, 16);
assert(g == 16.4);
assert(a == 2048);
end

function testAllDatasheetRanges(~)
ranges = [250 500 1000 2000];
expected = [131 65.5 32.8 16.4];
for i = 1:numel(ranges)
    assert(vs_imu_sensitivity(ranges(i)) == expected(i));
end
end

function testUnsupportedRangeIsAnError(~)
threw = false;
try
    vs_imu_sensitivity(1500, 16);
catch
    threw = true;
end
assert(threw, 'An unsupported gyro range must raise an error');
end
