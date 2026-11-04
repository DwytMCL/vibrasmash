function h = vs_file_hash(file)
%VS_FILE_HASH SHA-256 of a file, as 64 lowercase hex characters.
%
%   h = vs_file_hash(file)
%
%   Recorded in the run log for every input file, so a result can be traced
%   to the exact recording, reference and annotation files. Uses Octave's
%   hash() or, in MATLAB, Java's MessageDigest. Returns 'unavailable' when
%   neither exists (for example MATLAB started with -nojvm); the run log
%   then still lists the file's size and date.
%
%   Tests: tests/unit/test_report.m

fid = fopen(file, 'r');
if fid < 0
    error('vs_file_hash:missingFile', 'Cannot open %s', file);
end
bytes = fread(fid, Inf, '*uint8');
fclose(fid);
h = 'unavailable';
try
    if exist('OCTAVE_VERSION', 'builtin')
        h = hash('sha256', char(bytes(:).'));
    else
        md = java.security.MessageDigest.getInstance('SHA-256');
        if ~isempty(bytes)
            md.update(typecast(bytes(:), 'int8'));
        end
        d = typecast(md.digest(), 'uint8');
        h = lower(reshape(dec2hex(d, 2).', 1, []));
    end
catch
    h = 'unavailable';
end
end
