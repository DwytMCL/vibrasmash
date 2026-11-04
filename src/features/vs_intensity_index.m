function shots = vs_intensity_index(shots, meta, ref, cfg)
%VS_INTENSITY_INDEX Relative intensity index I = 100 x RMS / RMS_ref.
%
%   shots = vs_intensity_index(shots, meta, ref, cfg)
%
%   shots from vs_shot_features, meta the session's rec.meta, ref from
%   vs_reference_rms or [] when no reference session exists. Adds:
%     shots.intensity_index   cfg.features.intensity_scale x rms_v /
%                             ref.rms_ref_v for valid RMS values, else NaN
%     shots.index_note        why the index is empty, or the reference
%                             status when it is not 'ok'
%
%   A value of 100 is the reference response and values may exceed 100
%   (proposal). The index is not comparable across changed rackets, gain
%   settings or mounts, so a reference from another setup is an error, not
%   a warning.
%
%   Tests: tests/unit/test_features.m

n = numel(shots.shot);
shots.intensity_index = nan(n, 1);
shots.index_note = repmat({''}, n, 1);
if isempty(ref)
    shots.index_note(:) = {'no_reference'};
    return
end
setup = vs_setup_signature(meta);
if ~isequal(rmfield(setup, 'text'), rmfield(ref.setup, 'text'))
    error('vs_intensity_index:setupMismatch', ['Session %s (%s) does not share the ' ...
        'reference setup (%s); the index is not comparable across setups.'], ...
        meta.session_id, setup.text, ref.setup.text);
end
if isnan(ref.rms_ref_v)
    shots.index_note(:) = {'reference_has_no_valid_shots'};
    return
end
v = shots.rms_valid;
shots.intensity_index(v) = cfg.features.intensity_scale * shots.rms_v(v) / ref.rms_ref_v;
shots.index_note(~v) = {'rms_not_valid'};
if ~strcmp(ref.status, 'ok')
    shots.index_note(v) = {sprintf('reference_%s_%d_of_%d', ref.status, ref.n_valid, ref.n_expected)};
end
end
