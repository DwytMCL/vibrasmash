function meta = vs_read_meta(file)
%VS_READ_META Read a meta.txt file of 'key = value' lines.
%
%   meta = vs_read_meta(file)
%
%   Returns a struct whose fields are the keys and whose values are the
%   trimmed value strings, exactly as written. Lines starting with '#' and
%   blank lines are ignored. Errors (identifier vs_read_meta:*) on a line
%   without '=', an invalid key name, or a key given twice, so that an
%   ambiguous metadata file is never silently interpreted.
%
%   Tests: tests/unit/test_read_recording.m

fid = fopen(file, 'r');
if fid < 0
    error('vs_read_meta:open', 'Cannot open %s', file);
end
closer = onCleanup(@() fclose(fid));

meta = struct();
line_no = 0;
line = fgetl(fid);
while ischar(line)
    line_no = line_no + 1;
    s = strtrim(line);
    if ~isempty(s) && s(1) ~= '#'
        eq = find(s == '=', 1);
        if isempty(eq)
            error('vs_read_meta:syntax', '%s line %d has no "=": %s', file, line_no, s);
        end
        key = strtrim(s(1:eq-1));
        value = strtrim(s(eq+1:end));
        if isempty(regexp(key, '^[A-Za-z][A-Za-z0-9_]*$', 'once'))
            error('vs_read_meta:key', '%s line %d: invalid key "%s"', file, line_no, key);
        end
        if isfield(meta, key)
            error('vs_read_meta:duplicateKey', '%s line %d: key "%s" given twice', file, line_no, key);
        end
        meta.(key) = value;
    end
    line = fgetl(fid);
end
end
