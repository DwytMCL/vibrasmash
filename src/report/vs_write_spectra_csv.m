function vs_write_spectra_csv(file, res)
%VS_WRITE_SPECTRA_CSV One session's shot spectra as a wide CSV file.
%
%   vs_write_spectra_csv(file, res)
%
%   res from vs_process_session. Columns: freq_hz (bins labelled with the
%   measured rate, k x fs / 2048), then amp_v_shot<k> for every shot whose
%   spectrum was computed (complete window). Contaminated spectra are
%   written too; their flags are in shots.csv (fft_flags, fft_valid), so
%   the file never hides why a spectrum should not be trusted.
%
%   Tests: tests/unit/test_report.m

k = find(res.shots.fft_computed);
fid = fopen(file, 'w');
if fid < 0
    error('vs_write_spectra_csv:open', 'Cannot write %s', file);
end
closer = onCleanup(@() fclose(fid));
names = arrayfun(@(j) sprintf('amp_v_shot%d', res.shots.shot(j)), k(:).', 'UniformOutput', false);
fprintf(fid, '%s\n', strjoin([{'freq_hz'} names], ','));
M = [res.spectra.freq_hz res.spectra.amp(:, k)];
fmt = [strjoin(repmat({'%.8g'}, 1, size(M, 2)), ',') '\n'];
fprintf(fid, fmt, M.');
end
