function file = make_synthetic_annotations(fixture_folder, before_s, after_s)
%MAKE_SYNTHETIC_ANNOTATIONS Annotation file for a SYNTHETIC fixture, for tests.
%
%   file = make_synthetic_annotations(fixture_folder, before_s, after_s)
%
%   Turns the planted events in synthetic_truth.csv into one action
%   interval each, [t - before_s, t + after_s] on the ESP32 clock
%   (defaults 0.10 s and 0.05 s), in the format vs_read_annotations reads,
%   with split = test. It stands in for the operator's video annotation in
%   tests only. The file is written into the fixture folder as
%   synthetic_annotations.csv and refuses any folder that is not a
%   synthetic fixture.
%
%   Tests: tests/unit/test_analysis.m

if nargin < 2, before_s = 0.10; end
if nargin < 3, after_s = 0.05; end
truth = fullfile(fixture_folder, 'synthetic_truth.csv');
meta = vs_read_meta(fullfile(fixture_folder, 'meta.txt'));
if exist(truth, 'file') ~= 2 || ~isfield(meta, 'synthetic') || ~strcmpi(meta.synthetic, 'true')
    error('make_synthetic_annotations:notSynthetic', '%s is not a synthetic fixture', ...
        fixture_folder);
end
fid = fopen(truth, 'r');
fgetl(fid);
C = textscan(fid, '%f %s %f %*f %*f %*f %*f %*f %*f %*f', 'Delimiter', ',');
fclose(fid);
file = fullfile(fixture_folder, 'synthetic_annotations.csv');
fid = fopen(file, 'w');
closer = onCleanup(@() fclose(fid));
fprintf(fid, 'action_id,category,t_start_s,t_end_s,session,split\n');
for i = 1:numel(C{1})
    t = C{3}(i) / 1e6;
    fprintf(fid, '%d,%s,%.6f,%.6f,%s,test\n', C{1}(i), C{2}{i}, t - before_s, t + after_s, ...
        meta.session_id);
end
end
