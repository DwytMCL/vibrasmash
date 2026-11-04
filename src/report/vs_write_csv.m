function vs_write_csv(file, S, columns)
%VS_WRITE_CSV Write a struct of equal-length columns as a CSV file.
%
%   vs_write_csv(file, S, columns)
%
%   S        struct whose fields are column vectors (numeric, logical) or
%            cell arrays of text, all the same length
%   columns  optional cell array giving the column order (default: all
%            fields in order)
%
%   Numbers are written with up to 10 significant digits; NaN is written
%   as an empty cell, so undefined values never appear as 0. Logicals are
%   written as true / false. Text containing a comma, quote or line break
%   is quoted. Plain CSV, readable by MATLAB readtable, Excel or Python.
%
%   Tests: tests/unit/test_report.m

if nargin < 3 || isempty(columns)
    columns = fieldnames(S).';
end
n = numel(S.(columns{1}));
for c = 1:numel(columns)
    if numel(S.(columns{c})) ~= n
        error('vs_write_csv:length', 'Column %s has %d rows, expected %d', columns{c}, ...
            numel(S.(columns{c})), n);
    end
end
fid = fopen(file, 'w');
if fid < 0
    error('vs_write_csv:open', 'Cannot write %s', file);
end
closer = onCleanup(@() fclose(fid));
fprintf(fid, '%s\n', strjoin(columns, ','));
cells = cell(n, numel(columns));
for c = 1:numel(columns)
    v = S.(columns{c});
    for i = 1:n
        cells{i, c} = cell_text(v, i);
    end
end
for i = 1:n
    fprintf(fid, '%s\n', strjoin(cells(i, :), ','));
end
end

function t = cell_text(v, i)
if iscell(v)
    t = v{i};
    if isempty(t)
        t = '';
    elseif ~ischar(t)
        t = num2str(t);
    end
    if any(t == ',' | t == '"' | t == 10 | t == 13)
        t = ['"' strrep(t, '"', '""') '"'];
    end
elseif islogical(v)
    if v(i)
        t = 'true';
    else
        t = 'false';
    end
elseif isnan(v(i))
    t = '';
else
    t = sprintf('%.10g', v(i));
end
end
