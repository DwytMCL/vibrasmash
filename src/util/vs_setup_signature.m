function s = vs_setup_signature(meta)
%VS_SETUP_SIGNATURE The setup a reference response is tied to.
%
%   s = vs_setup_signature(meta)
%
%   Proposal: the index "is not comparable across changed rackets, gain
%   settings, or mounts". Returns a struct with the meta.txt values
%   afe_gain, mount_id and racket_id (as text) and s.text, one line for
%   reports. Two sessions share a setup only when all three are equal.
%
%   Tests: tests/unit/test_features.m

keys = {'afe_gain', 'mount_id', 'racket_id'};
parts = cell(1, numel(keys));
for i = 1:numel(keys)
    s.(keys{i}) = strtrim(meta.(keys{i}));
    parts{i} = sprintf('%s=%s', keys{i}, s.(keys{i}));
end
s.text = strjoin(parts, ', ');
end
