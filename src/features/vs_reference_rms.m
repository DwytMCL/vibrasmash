function ref = vs_reference_rms(results, cfg)
%VS_REFERENCE_RMS RMS_ref from separate controlled reference impacts.
%
%   ref = vs_reference_rms(results, cfg)
%
%   results is a cell array of session results (vs_process_session), each
%   a reference session: role 'reference' (vs_session_role) and
%   condition = middle in meta.txt. Proposal: RMS_ref is "the median
%   response from ten controlled reference impacts"; "ten separate
%   middle-condition impacts will establish the reference response".
%
%   RMS_ref = median of the valid 100 ms RMS values (shots.rms_valid) of all
%   reference sessions together. All sessions must share one setup
%   (vs_setup_signature); otherwise this is an error.
%
%   ref.rms_ref_v        median valid RMS (NaN if there is none)
%   ref.n_valid          valid reference shots used
%   ref.n_expected       cfg.features.reference_impact_count (10)
%   ref.n_attempted      all detections in the reference sessions
%   ref.status           'ok', 'shortfall' (fewer valid shots than
%                        expected), 'excess' (more), or 'no_valid_shots'
%   ref.note             one line for every output that uses the reference
%   ref.setup            the shared setup signature
%   ref.sessions         session ids; ref.folders their folders
%   ref.used             struct of columns: session_id, shot, rms_v
%   ref.synthetic        true if any reference session is synthetic
%
%   Tests: tests/unit/test_features.m

if isstruct(results)
    results = num2cell(results);
end
if isempty(results)
    error('vs_reference_rms:none', 'No reference sessions given');
end
ref.sessions = cell(1, numel(results));
ref.folders = cell(1, numel(results));
ref.synthetic = false;
ref.used.session_id = {};
ref.used.shot = [];
ref.used.rms_v = [];
ref.n_attempted = 0;
for k = 1:numel(results)
    r = results{k};
    sid = r.meta.session_id;
    if ~strcmp(vs_session_role(r.meta), 'reference')
        error('vs_reference_rms:notReference', ...
            'Session %s has role %s; reference impacts must come from reference sessions', ...
            sid, vs_session_role(r.meta));
    end
    if ~isfield(r.meta, 'condition') || ~strcmp(r.meta.condition, 'middle')
        error('vs_reference_rms:condition', ...
            'Reference session %s must have condition = middle in meta.txt', sid);
    end
    setup = vs_setup_signature(r.meta);
    if k == 1
        ref.setup = setup;
    elseif ~isequal(rmfield(setup, 'text'), rmfield(ref.setup, 'text'))
        error('vs_reference_rms:setupMismatch', ...
            'Reference sessions use different setups: %s versus %s', ref.setup.text, setup.text);
    end
    ref.sessions{k} = sid;
    ref.folders{k} = r.folder;
    ref.synthetic = ref.synthetic || r.synthetic;
    v = r.shots.rms_valid;
    ref.n_attempted = ref.n_attempted + numel(v);
    ref.used.session_id = [ref.used.session_id; r.shots.session_id(v)];
    ref.used.shot = [ref.used.shot; r.shots.shot(v)];
    ref.used.rms_v = [ref.used.rms_v; r.shots.rms_v(v)];
end

ref.n_valid = numel(ref.used.rms_v);
ref.n_expected = cfg.features.reference_impact_count;
if ref.n_valid == 0
    ref.rms_ref_v = NaN;
    ref.status = 'no_valid_shots';
else
    ref.rms_ref_v = median(ref.used.rms_v);
    if ref.n_valid < ref.n_expected
        ref.status = 'shortfall';
    elseif ref.n_valid > ref.n_expected
        ref.status = 'excess';
    else
        ref.status = 'ok';
    end
end
ref.note = sprintf('RMS_ref = median of %d valid reference shots (%d expected, %d detected): %s', ...
    ref.n_valid, ref.n_expected, ref.n_attempted, ref.status);
if ref.synthetic
    ref.note = ['SYNTHETIC reference. ' ref.note];
end
end
