function run = run_vibrasmash(opts)
%RUN_VIBRASMASH Process sessions and write every result, plot and log.
%
%   run = run_vibrasmash(opts)
%
%   opts.sessions     cell array of session folders to process (required)
%   opts.reference    cell array of reference session folders (role
%                     reference, condition = middle); {} leaves the
%                     intensity index empty
%   opts.annotations  cell array of annotation CSV files; when given, the
%                     annotated sessions are scored against them
%                     (evaluation data only); other sessions are listed as
%                     not scored
%   opts.cfg          settings (default: default_config()). The two pilot
%                     values, detect.noise_floor_threshold and
%                     detect.swing_confirm_threshold_dps, must be measured
%                     and set first; detection refuses to run without the
%                     noise floor
%   opts.out_root     where run folders go (default: <project>/results)
%   opts.label        short name for the run folder (default 'run')
%   opts.plots        true (default) to save PNG figures
%   opts.verbose      true to print each step as it starts (for debugging)
%
%   Steps: reference sessions -> RMS_ref (vs_reference_rms); each session
%   -> vs_process_session -> vs_intensity_index; all sessions ->
%   vs_consistency; with annotations -> vs_evaluate_detection. Outputs in
%   <out_root>/<yyyymmdd_HHMMSS>_<label>/ (prefixed synthetic_ when any
%   input is synthetic):
%     README.txt               what the folder holds; synthetic warning
%     run_log.txt              settings, input hashes, QC, reference, warnings
%     shots.csv                one row per detection of every session
%     reference_shots.csv      the same for the reference sessions
%     blocks.csv               block CVs, counts and reasons
%     qc.csv                   per-session QC summary
%     spectra/<session>.csv    shot spectra, bins at the measured rate
%     evaluation_summary.csv   TP, FP, FN, precision, recall, F1 per rule
%     evaluation_detections.csv, evaluation_actions.csv   every match
%     plots/<session>.png, plots/blocks.png
%
%   Example (real recordings, after pilot values are set):
%     cfg = default_config();
%     cfg.detect.noise_floor_threshold = <measured>;
%     run = run_vibrasmash(struct('sessions', {{'data/raw/S1'}}, ...
%         'reference', {{'data/reference/R1'}}, 'cfg', cfg));
%
%   scripts/demo_synthetic.m runs this end to end on labelled synthetic data.

% The path is not changed here (call vs_setup once beforehand): repeated
% path changes inside a MATLAB session were linked to an internal
% 'invalid vector subscript' error in MATLAB R2026b.
root = fileparts(fileparts(mfilename('fullpath')));
if ~isfield(opts, 'sessions') || isempty(opts.sessions)
    error('run_vibrasmash:noSessions', 'opts.sessions must list at least one session folder');
end
opts = defaults(opts, root);
cfg = opts.cfg;
warnings = {};

say(opts, 'start: %d session(s), %d reference session(s)', numel(opts.sessions), numel(opts.reference));

% ---- Reference
say(opts, 'processing reference sessions');
ref_results = cellfun(@(f) vs_process_session(f, cfg), opts.reference, 'UniformOutput', false);
if isempty(ref_results)
    ref = [];
    warnings{end+1} = 'No reference sessions: intensity index not computed';
else
    ref = vs_reference_rms(ref_results, cfg);
    if ~strcmp(ref.status, 'ok')
        warnings{end+1} = ref.note;
    end
    for k = 1:numel(ref_results)
        ref_results{k}.shots = vs_intensity_index(ref_results{k}.shots, ref_results{k}.meta, ref, cfg);
    end
end

say(opts, 'reference done');

% ---- Sessions
results = cell(numel(opts.sessions), 1);
for k = 1:numel(opts.sessions)
    say(opts, 'processing session %d: %s', k, opts.sessions{k});
    r = vs_process_session(opts.sessions{k}, cfg);
    r.shots = vs_intensity_index(r.shots, r.meta, ref, cfg);
    results{k} = r;
    if ~strcmp(r.qc.status, 'clean')
        warnings{end+1} = sprintf('%s QC flags: %s', r.meta.session_id, strjoin(r.qc.flags, ', ')); %#ok<AGROW>
    end
    if ~isempty(r.det.edge_candidates.t_us)
        warnings{end+1} = sprintf(['%s: %d threshold crossing(s) inside filter edge zones were ' ...
            'not counted (see run log)'], r.meta.session_id, numel(r.det.edge_candidates.t_us)); %#ok<AGROW>
    end
end
say(opts, 'block consistency');
blocks = vs_consistency(results, cfg);

% ---- Evaluation
say(opts, 'evaluation');
ev = [];
if ~isempty(opts.annotations)
    ann = vs_read_annotations(opts.annotations);
    % Only annotated sessions are scored (movement tests); controlled runs
    % and blocks without annotations are listed, not scored.
    sids = cellfun(@(r) r.meta.session_id, results, 'UniformOutput', false);
    scored = ismember(sids, ann.session);
    if any(~scored)
        warnings{end+1} = sprintf('Not scored for detection (no annotations): %s', ...
            strjoin(sids(~scored).', ', '));
    end
    ev = vs_evaluate_detection(results(scored), ann, cfg);
    warnings = [warnings ev.warnings];
end

% ---- Output folder
say(opts, 'creating the output folder');
synthetic = any(cellfun(@(r) r.synthetic, [ref_results(:); results(:)]));
c = clock();
stamp = sprintf('%04d%02d%02d_%02d%02d%02d', c(1:5), floor(c(6)));
name = [stamp '_' opts.label];
if synthetic
    name = ['synthetic_' name];
end
folder = fullfile(opts.out_root, name);
n = 1;
while exist(folder, 'dir')
    n = n + 1;
    folder = fullfile(opts.out_root, sprintf('%s_%d', name, n));
end
mkdir(folder);
mkdir(fullfile(folder, 'spectra'));
outputs = {};

% ---- CSV exports
shot_cols = {'session_id', 'shot', 'record_id', 'onset_t_us', 'onset_t_s', 'status', ...
    'accepted', 'swing_evaluated', 'swing_confirmed', 'swing_rule_applied', 'peak_envelope_v', ...
    'rms_v', 'rms_n_samples', 'rms_valid', 'rms_flags', 'intensity_index', 'index_note', ...
    'preimpact_peak_dps', 'preimpact_n_samples', 'preimpact_valid', 'preimpact_flags', ...
    'fft_computed', 'fft_valid', 'fft_flags', 'fft_peak_hz'};
say(opts, 'writing shots.csv');
outputs{end+1} = write_shots(fullfile(folder, 'shots.csv'), results, shot_cols, synthetic);
if ~isempty(ref_results)
    outputs{end+1} = write_shots(fullfile(folder, 'reference_shots.csv'), ref_results, ...
        shot_cols, synthetic);
end
blocks.data_source = source_column(blocks.synthetic);
say(opts, 'writing blocks.csv');
vs_write_csv(fullfile(folder, 'blocks.csv'), blocks, {'data_source', 'block', 'role', ...
    'condition', 'participant', 'block_no', 'n_detected', 'n_accepted', 'n_rejected', ...
    'rejected_reasons', 'rms_n_valid', 'rms_mean_v', 'rms_sd_v', 'rms_cv_pct', 'rms_status', ...
    'rms_invalid_reasons', 'index_mean', 'swing_n_valid', 'swing_mean_dps', 'swing_sd_dps', ...
    'swing_cv_pct', 'swing_status', 'swing_invalid_reasons', 'target_note'});
outputs{end+1} = fullfile(folder, 'blocks.csv');
say(opts, 'writing qc.csv');
outputs{end+1} = write_qc(fullfile(folder, 'qc.csv'), [ref_results(:); results(:)]);
say(opts, 'writing spectra');
for r = [ref_results(:); results(:)].'
    f = fullfile(folder, 'spectra', [r{1}.meta.session_id '.csv']);
    vs_write_spectra_csv(f, r{1});
    outputs{end+1} = f; %#ok<AGROW>
end
if ~isempty(ev)
    outputs = [outputs write_evaluation(folder, ev)];
end

% ---- Plots
say(opts, 'evaluation files done; plots = %d', opts.plots);
if opts.plots
    pdir = fullfile(folder, 'plots');
    mkdir(pdir);
    for r = [ref_results(:); results(:)].'
        say(opts, 'plotting %s', r{1}.meta.session_id);
        outputs{end+1} = vs_plot_session(r{1}, cfg, pdir); %#ok<AGROW>
    end
    say(opts, 'plotting blocks');
    outputs{end+1} = vs_plot_blocks(blocks, results, pdir, synthetic);
    drawnow;
    say(opts, 'plots done');
end

% ---- Run record
say(opts, 'building the run record');
run.run_id = name;
run.created = sprintf('%04d-%02d-%02d %02d:%02d:%02d (computer clock)', c(1:5), floor(c(6)));
run.platform = platform_text();
run.folder = folder;
run.cfg = cfg;
run.synthetic = synthetic;
run.ref = ref;
run.reference_results = ref_results;
run.results = results;
run.blocks = blocks;
run.evaluation = ev;
run.warnings = warnings;
run.inputs = input_files(opts);
outputs = [{fullfile(folder, 'README.txt'), fullfile(folder, 'run_log.txt')} outputs];
run.outputs = outputs;
say(opts, 'writing run_log.txt');
run.verbose = opts.verbose;
vs_write_run_log(fullfile(folder, 'run_log.txt'), run);
say(opts, 'writing README.txt');
write_readme(fullfile(folder, 'README.txt'), run);
fprintf('VibraSmash run written to %s\n', folder);
if synthetic
    fprintf('SYNTHETIC TEST DATA: nothing in this run is a measurement.\n');
end
end

% -------------------------------------------------------------------------

function say(opts, fmt, varargin)
if opts.verbose
    fprintf(['  [run_vibrasmash] ' fmt '\n'], varargin{:});
end
end

function opts = defaults(opts, root)
d.reference = {};
d.annotations = {};
d.cfg = [];
d.out_root = fullfile(root, 'results');
d.label = 'run';
d.plots = true;
d.verbose = false;
f = fieldnames(d);
for i = 1:numel(f)
    if ~isfield(opts, f{i})
        opts.(f{i}) = d.(f{i});
    end
end
if isempty(opts.cfg)
    opts.cfg = default_config();
end
if ischar(opts.sessions), opts.sessions = {opts.sessions}; end
if ischar(opts.reference), opts.reference = {opts.reference}; end
if ischar(opts.annotations), opts.annotations = {opts.annotations}; end
if isempty(regexp(opts.label, '^[A-Za-z0-9_-]+$', 'once'))
    error('run_vibrasmash:label', 'opts.label must use letters, digits, _ or - only');
end
if ~exist(opts.out_root, 'dir')
    mkdir(opts.out_root);
end
end

function c = source_column(synthetic)
c = repmat({'real'}, numel(synthetic), 1);
c(synthetic) = {'SYNTHETIC'};
end

function file = write_shots(file, results, cols, ~)
% Start from the first session's (possibly empty) columns so each column
% keeps its type (logical stays logical, text stays text).
S = struct();
for c = cols
    S.(c{1}) = results{1}.shots.(c{1})([], 1);
end
S.data_source = cell(0, 1);
S.role = cell(0, 1);
for k = 1:numel(results)
    s = results{k}.shots;
    n = numel(s.shot);
    for c = cols
        S.(c{1}) = [S.(c{1}); s.(c{1})];
    end
    S.data_source = [S.data_source; source_column(repmat(results{k}.synthetic, n, 1))];
    S.role = [S.role; repmat({results{k}.role}, n, 1)];
end
vs_write_csv(file, S, [{'data_source', 'role'} cols]);
end

function file = write_qc(file, results)
n = numel(results);
Q.data_source = source_column(cellfun(@(r) r.synthetic, results));
Q.session_id = cellfun(@(r) r.meta.session_id, results, 'UniformOutput', false);
Q.role = cellfun(@(r) r.role, results, 'UniformOutput', false);
Q.qc_status = cellfun(@(r) r.qc.status, results, 'UniformOutput', false);
Q.qc_flags = cellfun(@(r) strjoin(r.qc.flags, ';'), results, 'UniformOutput', false);
Q.piezo_measured_fs_hz = cellfun(@(r) r.qc.piezo.measured_fs_hz, results);
Q.imu_measured_fs_hz = cellfun(@(r) r.qc.imu.measured_fs_hz, results);
Q.piezo_missing_pct = cellfun(@(r) r.qc.piezo.missing_pct, results);
Q.imu_missing_pct = cellfun(@(r) r.qc.imu.missing_pct, results);
Q.piezo_clipped_pct = cellfun(@(r) r.qc.piezo.clipped_pct, results);
Q.imu_gyro_clipped_samples = cellfun(@(r) r.qc.imu.n_gyro_clipped, results);
Q.edge_candidates = cellfun(@(r) numel(r.det.edge_candidates.t_us), results);
Q.processing_s = cellfun(@(r) r.elapsed_s, results);
if n == 0
    return
end
vs_write_csv(file, Q);
end

function files = write_evaluation(folder, ev)
R = ev.rules;
E.data_source = repmat({ternary(ev.synthetic, 'SYNTHETIC', 'real')}, numel(R), 1);
fields = {'name', 'evaluated', 'n_contacts', 'n_detections', 'tp', 'fp', 'fn', 'precision', ...
    'recall', 'f1', 'meets_precision_target', 'meets_recall_target', 'fp_in_dry_swing', ...
    'fp_in_handling', 'fp_in_frame_tap', 'fp_duplicate', 'fp_spurious', 'fp_ambiguous', ...
    'dry_swing_actions', 'dry_swing_correct_rejections', 'handling_actions', ...
    'handling_correct_rejections', 'frame_tap_actions', 'frame_tap_correct_rejections', 'note'};
for i = 1:numel(fields)
    v = {R.(fields{i})}.';
    if ischar(v{1})
        E.(fields{i}) = v;
    elseif islogical(v{1})
        E.(fields{i}) = logical([v{:}]).';
    else
        E.(fields{i}) = [v{:}].';
    end
end
E.tolerance_s = repmat(ev.tolerance_s, numel(R), 1);
files = {fullfile(folder, 'evaluation_summary.csv'), fullfile(folder, 'evaluation_detections.csv'), ...
    fullfile(folder, 'evaluation_actions.csv')};
vs_write_csv(files{1}, E);
vs_write_csv(files{2}, ev.detections);
vs_write_csv(files{3}, ev.actions);
end

function t = ternary(c, a, b)
if c
    t = a;
else
    t = b;
end
end

function f = input_files(opts)
f = {};
for d = [opts.reference(:); opts.sessions(:)].'
    f = [f, {fullfile(d{1}, 'meta.txt'), fullfile(d{1}, 'piezo.csv'), ...
        fullfile(d{1}, 'imu.csv')}]; %#ok<AGROW>
end
f = [f, opts.annotations(:).'];
end

function t = platform_text()
if exist('OCTAVE_VERSION', 'builtin')
    t = sprintf('GNU Octave %s on %s', OCTAVE_VERSION, computer());
else
    t = sprintf('MATLAB %s on %s', version(), computer());
end
end

function write_readme(file, run)
fid = fopen(file, 'w');
closer = onCleanup(@() fclose(fid));
if run.synthetic
    fprintf(fid, ['SYNTHETIC TEST DATA\n\nThis folder was produced from synthetic test ' ...
        'fixtures. Nothing in it is a\nmeasurement, an experimental result or evidence that ' ...
        'the ESP32 hardware works.\nDo not report any number from it as a VibraSmash ' ...
        'result.\n\n']);
end
fprintf(fid, 'VibraSmash run %s, created %s\n\n', run.run_id, run.created);
fprintf(fid, 'run_log.txt              settings with sources, input file hashes, QC, reference\n');
fprintf(fid, 'shots.csv                one row per detection (data_source column says real or SYNTHETIC)\n');
fprintf(fid, 'reference_shots.csv      reference session detections (when a reference was given)\n');
fprintf(fid, 'blocks.csv               block CVs for impact RMS and pre-impact peak angular speed\n');
fprintf(fid, 'qc.csv                   per-session sampling, missing-sample and clipping summary\n');
fprintf(fid, 'spectra/<session>.csv    2048-sample Hann FFT per shot (exploratory diagnostic)\n');
fprintf(fid, 'evaluation_*.csv         detection evaluation (only when annotations were given)\n');
fprintf(fid, 'plots/                   session figures and the block summary\n\n');
fprintf(fid, ['Empty CSV cells mean "not defined" (for example a CV from fewer than two\n' ...
    'valid shots, or precision with no detections), never zero.\n']);
fprintf(fid, ['The intensity index is relative to this run''s reference and is not comparable\n' ...
    'across changed rackets, gain settings or mounts.\n']);
end
