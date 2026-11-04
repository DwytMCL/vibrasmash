function [gyro_lsb_per_dps, accel_lsb_per_g] = vs_imu_sensitivity(gyro_range_dps, accel_range_g)
%VS_IMU_SENSITIVITY MPU-6050 scale factors for the configured full-scale ranges.
%
%   [gyro_lsb_per_dps, accel_lsb_per_g] = vs_imu_sensitivity(gyro_range_dps, accel_range_g)
%
%   Values are the sensitivity scale factors in the InvenSense MPU-6000/MPU-6050
%   Product Specification, Rev. 3.4 (proposal reference [8]):
%     gyro  +/-250, 500, 1000, 2000 deg/s -> 131, 65.5, 32.8, 16.4 LSB/(deg/s)
%     accel +/-2, 4, 8, 16 g              -> 16384, 8192, 4096, 2048 LSB/g
%   Any other range is an error, so a typo in meta.txt cannot silently rescale data.
%
%   Tests: tests/unit/test_imu_sensitivity.m

gyro_ranges = [250 500 1000 2000];
gyro_lsb = [131 65.5 32.8 16.4];
accel_ranges = [2 4 8 16];
accel_lsb = [16384 8192 4096 2048];

ig = find(gyro_ranges == gyro_range_dps, 1);
if isempty(ig)
    error('vs_imu_sensitivity:gyroRange', ...
        'Unsupported gyro range %g deg/s; expected 250, 500, 1000 or 2000.', gyro_range_dps);
end
gyro_lsb_per_dps = gyro_lsb(ig);

if nargin < 2
    accel_lsb_per_g = [];
    return
end
ia = find(accel_ranges == accel_range_g, 1);
if isempty(ia)
    error('vs_imu_sensitivity:accelRange', ...
        'Unsupported accel range %g g; expected 2, 4, 8 or 16.', accel_range_g);
end
accel_lsb_per_g = accel_lsb(ia);
end
