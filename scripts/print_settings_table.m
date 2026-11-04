function print_settings_table()
%PRINT_SETTINGS_TABLE Print every setting as a Markdown table, by provenance.
%
%   Keeps docs/settings_provenance.md in step with config/default_config.m.
%     addpath scripts; print_settings_table

addpath(fileparts(fileparts(mfilename('fullpath'))));
vs_setup();
cfg = default_config();
S = cfg.provenance;

sources = {'proposal', 'provisional', 'pilot'};
for s = 1:numel(sources)
    idx = find(strcmp(S(:,3), sources{s})).';
    fprintf('\n### Source: %s (%d settings)\n\n', sources{s}, numel(idx));
    fprintf('| Setting | Value | Note |\n| --- | --- | --- |\n');
    for i = idx
        fprintf('| `%s` | %s | %s |\n', S{i,1}, value_text(S{i,2}), S{i,4});
    end
end
end

function txt = value_text(v)
if isempty(v)
    txt = '(not set)';
elseif ischar(v)
    txt = v;
elseif islogical(v)
    if v
        txt = 'true';
    else
        txt = 'false';
    end
else
    txt = num2str(v);
end
end
