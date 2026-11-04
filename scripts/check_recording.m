function qc = check_recording(folder)
%CHECK_RECORDING Read one session folder and print its quality-control report.
%
%   qc = check_recording(folder)
%
%   Use this on the first ESP32 files to see the measured sampling rates,
%   gaps, timestamp problems and clipping before any processing. It only
%   reads and reports; it changes nothing.
%
%   Example, on a synthetic test folder:
%     spec = make_synthetic_fixture(); spec.out_dir = tempdir;
%     info = make_synthetic_fixture(spec);
%     check_recording(info.folder);

vs_setup();
cfg = default_config();
rec = vs_read_recording(folder);
qc = vs_validate_recording(rec, cfg);
fprintf('%s', vs_qc_summary(qc));
fprintf('Conversions:\n  piezo: %s\n  gyro:  %s\n  accel: %s\n  time:  %s\n', ...
    rec.conversion.piezo, rec.conversion.gyro, rec.conversion.accel, rec.conversion.time);
end
