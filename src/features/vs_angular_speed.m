function w = vs_angular_speed(gyro_dps)
%VS_ANGULAR_SPEED Angular-speed magnitude from three gyroscope axes.
%
%   w = vs_angular_speed(gyro_dps)
%
%   gyro_dps is N-by-3 (deg/s). Proposal: "the square root of the sum of
%   squared gyroscope axes". This is a shaft angular-motion feature, not
%   racket-head speed.
%
%   Tests: tests/unit/test_detect.m

w = sqrt(sum(gyro_dps.^2, 2));
end
