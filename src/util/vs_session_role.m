function role = vs_session_role(meta)
%VS_SESSION_ROLE What a session is for: reference, controlled, stroke, ...
%
%   role = vs_session_role(meta)
%
%   meta is rec.meta (vs_read_meta). Returns meta.session_type, except for
%   synthetic test sessions (synthetic = true) that carry a synthetic_role
%   key, which returns that role. A synthetic session stays labelled
%   synthetic in every output; the role only lets tests exercise the
%   reference, consistency and evaluation steps.
%
%   Tests: tests/unit/test_features.m

role = meta.session_type;
if isfield(meta, 'synthetic') && strcmpi(meta.synthetic, 'true') && isfield(meta, 'synthetic_role')
    role = meta.synthetic_role;
end
end
