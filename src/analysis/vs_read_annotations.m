function ann = vs_read_annotations(files)
%VS_READ_ANNOTATIONS Read and check ground-truth action annotation files.
%
%   ann = vs_read_annotations(file)
%   ann = vs_read_annotations({file1, file2, ...})   rows are concatenated
%
%   CSV with the header
%     action_id,category,t_start_s,t_end_s,session,split
%   one row per performed action, from the phone video and the operator's
%   trial log (proposal). Times are seconds on the ESP32 clock, that is
%   t_us / 1e6 of the recording, mapped from video by the operator.
%   category is contact, dry_swing, handling or frame_tap. session is the
%   session_id in meta.txt. Columns may be in any order.
%
%   Errors (vs_read_annotations:*) on anything that would make matching
%   ambiguous: a missing column, an unknown category, t_end_s < t_start_s,
%   an action_id repeated within one session, or overlapping intervals
%   within one session.
%   Overlaps are annotation errors and are never resolved silently.
%
%   ann is a struct of columns plus ann.files.
%
%   Tests: tests/unit/test_analysis.m

if ischar(files)
    files = {files};
end
cols = {'action_id', 'category', 't_start_s', 't_end_s', 'session', 'split'};
for c = cols
    ann.(c{1}) = cell(0, 1);
end
ann.action_id = zeros(0, 1);
ann.t_start_s = zeros(0, 1);
ann.t_end_s = zeros(0, 1);
for k = 1:numel(files)
    a = read_one(files{k}, cols);
    for c = cols
        ann.(c{1}) = [ann.(c{1}); a.(c{1})];
    end
end
ann.files = files;
check(ann);
end

% -------------------------------------------------------------------------

function ann = read_one(file, cols)
fid = fopen(file, 'r');
if fid < 0
    error('vs_read_annotations:missingFile', 'Cannot open %s', file);
end
closer = onCleanup(@() fclose(fid));
txt = fread(fid, Inf, '*char').';
lines = regexp(txt, '\r?\n', 'split');
lines = lines(~cellfun(@(l) isempty(strtrim(l)), lines));
if isempty(lines)
    error('vs_read_annotations:empty', '%s is empty', file);
end
header = strtrim(strsplit(lines{1}, ','));
missing = cols(~ismember(cols, header));
if ~isempty(missing)
    error('vs_read_annotations:missingColumn', '%s is missing columns: %s', file, ...
        strjoin(missing, ', '));
end
n = numel(lines) - 1;
raw = cell(n, numel(header));
for i = 1:n
    f = strtrim(strsplit(lines{i + 1}, ','));
    if numel(f) ~= numel(header)
        error('vs_read_annotations:row', 'Row %d has %d fields, expected %d', i, ...
            numel(f), numel(header));
    end
    raw(i, :) = f;
end
col = @(name) raw(:, strcmp(header, name));
ann.action_id = to_number(col('action_id'), 'action_id');
ann.category = col('category');
ann.t_start_s = to_number(col('t_start_s'), 't_start_s');
ann.t_end_s = to_number(col('t_end_s'), 't_end_s');
ann.session = col('session');
ann.split = col('split');
end

function check(ann)
valid = {'contact', 'dry_swing', 'handling', 'frame_tap'};
bad = ~ismember(ann.category, valid);
if any(bad)
    error('vs_read_annotations:category', 'Unknown category "%s" (allowed: %s)', ...
        ann.category{find(bad, 1)}, strjoin(valid, ', '));
end
if any(ann.t_end_s < ann.t_start_s)
    error('vs_read_annotations:interval', 'Action %d ends before it starts', ...
        ann.action_id(find(ann.t_end_s < ann.t_start_s, 1)));
end
sessions = unique(ann.session);
for k = 1:numel(sessions)
    i = find(strcmp(ann.session, sessions{k}));
    if numel(unique(ann.action_id(i))) ~= numel(i)
        error('vs_read_annotations:duplicateId', ...
            'action_id values must be unique within session %s', sessions{k});
    end
    [ts, o] = sort(ann.t_start_s(i));
    te = ann.t_end_s(i(o));
    clash = find(ts(2:end) <= te(1:end-1), 1);
    if ~isempty(clash)
        error('vs_read_annotations:overlap', 'Actions %d and %d overlap in session %s', ...
            ann.action_id(i(o(clash))), ann.action_id(i(o(clash + 1))), sessions{k});
    end
end
end

function x = to_number(c, name)
x = str2double(c);
if any(isnan(x))
    error('vs_read_annotations:number', 'Column %s has a non-numeric value', name);
end
end
