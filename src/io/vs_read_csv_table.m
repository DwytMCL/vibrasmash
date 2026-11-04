function T = vs_read_csv_table(file)
%VS_READ_CSV_TABLE Read a numeric CSV file with one header line.
%
%   T = vs_read_csv_table(file)
%
%   Returns a struct with:
%     T.file     the file path
%     T.header   1-by-N cell array of column names, in file order
%     T.data     M-by-N double matrix, rows in file order (never re-ordered)
%     T.(name)   one M-by-1 column per header name
%
%   Empty cells become NaN, so they can be flagged later rather than lost.
%   Errors (identifier vs_read_csv_table:*) when the file cannot be opened,
%   has no header, has an invalid or duplicate column name, or contains
%   non-numeric text after the header.
%
%   Tests: tests/unit/test_read_recording.m

fid = fopen(file, 'r');
if fid < 0
    error('vs_read_csv_table:open', 'Cannot open %s', file);
end
closer = onCleanup(@() fclose(fid));

hdr = fgetl(fid);
if ~ischar(hdr) || isempty(strtrim(hdr))
    error('vs_read_csv_table:header', 'No header line in %s', file);
end
names = strtrim(strsplit(hdr, ','));
for i = 1:numel(names)
    if isempty(regexp(names{i}, '^[A-Za-z][A-Za-z0-9_]*$', 'once'))
        error('vs_read_csv_table:columnName', 'Invalid column name "%s" in %s', names{i}, file);
    end
end
if numel(unique(names)) ~= numel(names)
    error('vs_read_csv_table:duplicateColumn', 'Duplicate column name in %s', file);
end

n = numel(names);
C = textscan(fid, repmat('%f', 1, n), 'Delimiter', ',', 'EmptyValue', NaN);
lens = cellfun(@numel, C);
m = min(lens);
data = zeros(m, n);
for i = 1:n
    data(:, i) = C{i}(1:m);
end

% textscan stops at the first field it cannot parse. A partly read row, or
% any text left after it, means non-numeric content.
rest = fgetl(fid);
while ischar(rest) && isempty(strtrim(rest))
    rest = fgetl(fid);
end
if any(lens ~= m) || ischar(rest)
    if ~ischar(rest)
        rest = '';
    end
    error('vs_read_csv_table:nonNumeric', ...
        'Non-numeric content in %s after data row %d: "%s"', file, m, strtrim(rest));
end

T.file = file;
T.header = names;
T.data = data;
for i = 1:n
    T.(names{i}) = data(:, i);
end
end
