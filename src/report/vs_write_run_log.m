function vs_write_run_log(file, run)
%VS_WRITE_RUN_LOG Text record of everything needed to reproduce a run.
%
%   vs_write_run_log(file, run)
%
%   run is the struct built by run_vibrasmash. The log lists: the run id
%   and time, the software platform, the config version and every setting
%   with its source (proposal / provisional / pilot), any setting that
%   differs from default_config (pilot values set by the caller included),
%   every input file with its size, date and SHA-256, the reference used
%   and its shots, each session's QC status and flags, the detection and
%   evaluation warnings, and the processing times. Synthetic runs say so
%   at the top. Proposal: "Raw records, processing settings, and results
%   will be retained so that the calculations can be reproduced."
%
%   Tests: tests/integration/test_pipeline.m

fid = fopen(file, 'w');
if fid < 0
    error('vs_write_run_log:open', 'Cannot write %s', file);
end
closer = onCleanup(@() fclose(fid));
cfg = run.cfg;
p = @(varargin) fprintf(fid, varargin{:});
verbose = isfield(run, 'verbose') && run.verbose;

p('# VibraSmash run log\n');
if run.synthetic
    p('# SYNTHETIC TEST DATA. Nothing in this run is a measurement or an\n');
    p('# experimental result, and it must never be reported as one.\n');
end
p('run_id = %s\n', run.run_id);
p('created = %s\n', run.created);
p('platform = %s\n', run.platform);
p('config_version = %s\n', cfg.config_version);
p('output_folder = %s\n\n', run.folder);

trace(verbose, 'Settings (source: proposal / provisional / pilot)');
p('## Settings (source: proposal / provisional / pilot)\n');
S = cfg.provenance;
D = default_config();
for i = 1:size(S, 1)
    parts = strsplit(S{i, 1}, '.');
    used = getfield(cfg, parts{:}); %#ok<GFLD>
    default = getfield(D, parts{:}); %#ok<GFLD>
    mark = '';
    if ~isequal(used, default)
        mark = sprintf('   <-- CHANGED from default %s', value_text(default));
    end
    p('%-42s = %-16s [%s]%s\n', S{i, 1}, value_text(used), S{i, 3}, mark);
end
p('\n');

trace(verbose, 'Input files');
p('## Input files\n');
for i = 1:numel(run.inputs)
    f = run.inputs{i};
    d = dir(f);
    if isempty(d)
        p('%s  MISSING\n', f);
    else
        trace(verbose, ['hashing ' f]);
        p('%s  bytes=%d  modified=%s  sha256=%s\n', f, d.bytes, d.date, vs_file_hash(f));
    end
end
p('\n');

trace(verbose, 'Reference');
p('## Reference\n');
if isempty(run.ref)
    p('No reference sessions: the intensity index is left empty. RMS is still reported.\n\n');
else
    r = run.ref;
    p('%s\n', r.note);
    p('RMS_ref_v = %.8g\n', r.rms_ref_v);
    p('setup = %s\n', r.setup.text);
    p('sessions = %s\n', strjoin(r.sessions, ', '));
    for i = 1:numel(r.used.rms_v)
        p('  used: %s shot %d rms_v = %.8g\n', r.used.session_id{i}, r.used.shot(i), r.used.rms_v(i));
    end
    p('\n');
end

trace(verbose, 'Sessions');
p('## Sessions\n');
all_res = [run.reference_results(:); run.results(:)];
for i = 1:numel(all_res)
    res = all_res{i};
    s = res.shots;
    p('%s  role=%s  synthetic=%d  qc=%s  piezo_fs=%.3f Hz  imu_fs=%.3f Hz\n', ...
        res.meta.session_id, res.role, res.synthetic, res.qc.status, ...
        res.qc.piezo.measured_fs_hz, res.qc.imu.measured_fs_hz);
    p('  qc flags: %s\n', strjoin(res.qc.flags, ', '));
    p('  missing: piezo %.3f%%, imu %.3f%%; piezo clipped %.3f%%\n', ...
        res.qc.piezo.missing_pct, res.qc.imu.missing_pct, res.qc.piezo.clipped_pct);
    p('  detections %d, accepted %d, rejected %d, edge candidates %d, swing rule applied %d\n', ...
        numel(s.shot), sum(s.accepted), sum(~s.accepted), ...
        numel(res.det.edge_candidates.t_us), res.det.swing_rule_applied);
    p('  valid: rms %d, pre-impact %d, spectrum %d\n', sum(s.rms_valid), ...
        sum(s.preimpact_valid), sum(s.fft_valid));
    for k = 1:numel(res.det.thresholds)
        t = res.det.thresholds(k);
        p('  record %d threshold %.6g V\n', t.record_id, t.threshold_v);
    end
    for k = 1:numel(res.pre.notes)
        p('  note: %s\n', res.pre.notes{k});
    end
    p('  processing time on this computer: %.3f s (software timing only)\n', res.elapsed_s);
end
p('\n');

trace(verbose, 'Warnings');
p('## Warnings\n');
if isempty(run.warnings)
    p('none\n');
else
    p('%s\n', run.warnings{:});
end
p('\n## Outputs\n');
p('%s\n', run.outputs{:});
end

function trace(verbose, msg)
if verbose
    fprintf('  [run log] %s\n', msg);
end
end

function t = value_text(v)
if isempty(v)
    t = '[] (not set)';
elseif ischar(v)
    t = v;
elseif islogical(v)
    t = mat2str(v);
else
    t = num2str(v, 10);
end
end
