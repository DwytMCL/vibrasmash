function res = vs_process_session(folder, cfg)
%VS_PROCESS_SESSION Read, validate, filter, detect and measure one session.
%
%   res = vs_process_session(folder, cfg)
%
%   Runs the per-session steps in the proposal's order:
%   vs_read_recording -> vs_validate_recording -> vs_preprocess ->
%   vs_detect_impacts -> vs_shot_features. The intensity index needs the
%   reference and is added afterwards (vs_intensity_index).
%
%   res.folder, res.meta, res.role, res.synthetic, res.setup, res.rec,
%   res.qc, res.pre, res.det, res.shots, res.spectra, res.elapsed_s
%   (processing time on this computer, for the proposal's one-second
%   display target; it is a software timing, not a hardware result).
%
%   Tests: tests/unit/test_features.m, tests/integration/test_pipeline.m

t_start = tic;
rec = vs_read_recording(folder);
qc = vs_validate_recording(rec, cfg);
pre = vs_preprocess(rec, qc, cfg);
det = vs_detect_impacts(rec, qc, pre, cfg);
[shots, spectra] = vs_shot_features(rec, qc, pre, det, cfg);

res.folder = folder;
res.meta = rec.meta;
res.role = vs_session_role(rec.meta);
res.synthetic = rec.synthetic;
res.setup = vs_setup_signature(rec.meta);
res.rec = rec;
res.qc = qc;
res.pre = pre;
res.det = det;
res.shots = shots;
res.spectra = spectra;
res.elapsed_s = toc(t_start);
end
