function txt = vs_qc_summary(qc)
%VS_QC_SUMMARY Plain-text summary of a vs_validate_recording result.
%
%   txt = vs_qc_summary(qc)
%
%   Returns a char array with one line per item, suitable for printing with
%   fprintf('%s', txt) or saving into a run log.
%
%   Tests: tests/unit/test_validate_recording.m

L = {};
L{end+1} = sprintf('Session: %s', qc.session_id);
if qc.synthetic
    L{end+1} = 'SYNTHETIC TEST DATA - not a measurement';
end
L{end+1} = sprintf('Status: %s', qc.status);
streams = {'piezo', 'imu'};
for i = 1:2
    s = qc.(streams{i});
    L{end+1} = sprintf(['%s: %d samples in %d record(s); measured %.2f Hz vs nominal %g Hz ' ...
        '(%+.2f%%); missing %d (%.3f%%) in %d gap(s); %d backwards, %d duplicate timestamps; ' ...
        'interval p05/p50/p95 = %g/%g/%g us'], ...
        streams{i}, s.n_samples, s.n_records, s.measured_fs_hz, s.nominal_fs_hz, ...
        s.rate_deviation_pct, s.missing_samples, s.missing_pct, s.n_gaps, ...
        s.n_backwards, s.n_duplicates, s.dt_p05_us, s.dt_p50_us, s.dt_p95_us); %#ok<AGROW>
end
L{end+1} = sprintf('piezo clipped samples: %d (%.3f%%); bias measured %.1f mV, expected %g mV', ...
    qc.piezo.n_clipped, qc.piezo.clipped_pct, qc.piezo.bias_measured_mv, qc.piezo.bias_expected_mv);
L{end+1} = sprintf('imu clipped samples: gyro %d, accel %d', ...
    qc.imu.n_gyro_clipped, qc.imu.n_accel_clipped);
L{end+1} = sprintf('Minimum record length for feature windows: %.4f s', qc.min_record_s);
if isempty(qc.flags)
    L{end+1} = 'Flags: none';
else
    L{end+1} = sprintf('Flags: %s', strjoin(qc.flags, ', '));
end
for i = 1:numel(qc.notes)
    L{end+1} = sprintf('Note: %s', qc.notes{i}); %#ok<AGROW>
end
txt = sprintf('%s\n', L{:});
end
