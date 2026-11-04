function blocks = vs_consistency(results, cfg)
%VS_CONSISTENCY Block-level CVs for impact RMS and pre-impact angular speed.
%
%   blocks = vs_consistency(results, cfg)
%
%   results is a cell array of session results (vs_process_session, with
%   vs_intensity_index applied). One block = one session folder
%   (cfg.consistency.block_key = 'session'): one ten-shot controlled run or
%   one volunteer block. Proposal: "Consistency will be reported separately
%   for impact RMS and pre-impact peak angular speed. For a block of valid
%   shots, CV = 100 x sample standard deviation/mean."
%
%   Each CV uses that feature's valid shots only (shots.rms_valid,
%   shots.preimpact_valid), so a shot with a clean RMS window but a broken
%   swing window still counts for RMS. A block with fewer than
%   cfg.consistency.min_valid_shots (8) valid values for a feature is
%   'insufficient' for that feature; its CV is still calculated and
%   exported, labelled, and kept out of any ten-shot summary.
%
%   Stationary sessions (role reference or controlled) have no swing, so
%   their angular-speed CV is not computed (status 'stationary_session').
%   For controlled middle-condition blocks the RMS CV is compared with the
%   proposal's 15% target; the comparison is reported, never used to tune.
%
%   blocks is a struct of columns, one element per block: block, role,
%   condition, participant, block_no, synthetic, n_detected, n_accepted,
%   n_rejected, rejected_reasons, rms_n_valid, rms_mean_v, rms_sd_v,
%   rms_cv_pct, rms_status, rms_invalid_reasons, index_mean, swing_n_valid,
%   swing_mean_dps, swing_sd_dps, swing_cv_pct, swing_status,
%   swing_invalid_reasons, target_note.
%
%   Tests: tests/unit/test_analysis.m

if ~strcmp(cfg.consistency.block_key, 'session')
    error('vs_consistency:blockKey', 'Only consistency.block_key = session is implemented');
end
if isstruct(results)
    results = num2cell(results);
end
nb = numel(results);
text_cols = {'block', 'role', 'condition', 'participant', 'block_no', 'rejected_reasons', ...
    'rms_status', 'rms_invalid_reasons', 'swing_status', 'swing_invalid_reasons', 'target_note'};
num_cols = {'n_detected', 'n_accepted', 'n_rejected', 'rms_n_valid', 'rms_mean_v', ...
    'rms_sd_v', 'rms_cv_pct', 'index_mean', 'swing_n_valid', 'swing_mean_dps', ...
    'swing_sd_dps', 'swing_cv_pct'};
for i = 1:numel(text_cols)
    blocks.(text_cols{i}) = repmat({''}, nb, 1);
end
for i = 1:numel(num_cols)
    blocks.(num_cols{i}) = nan(nb, 1);
end
blocks.synthetic = false(nb, 1);
min_n = cfg.consistency.min_valid_shots;

for b = 1:nb
    r = results{b};
    s = r.shots;
    blocks.block{b} = r.meta.session_id;
    blocks.role{b} = r.role;
    blocks.condition{b} = meta_text(r.meta, 'condition');
    blocks.participant{b} = meta_text(r.meta, 'participant');
    blocks.block_no{b} = meta_text(r.meta, 'block');
    blocks.synthetic(b) = r.synthetic;
    blocks.n_detected(b) = numel(s.shot);
    blocks.n_accepted(b) = sum(s.accepted);
    blocks.n_rejected(b) = sum(~s.accepted);
    blocks.rejected_reasons{b} = count_codes(s.status(~s.accepted));

    v = s.rms_valid;
    [blocks.rms_cv_pct(b), blocks.rms_mean_v(b), blocks.rms_sd_v(b)] = vs_cv(s.rms_v(v));
    blocks.rms_n_valid(b) = sum(v);
    blocks.rms_status{b} = status(sum(v), min_n);
    blocks.rms_invalid_reasons{b} = count_codes(split_codes(s.rms_flags(s.accepted & ~v)));
    if isfield(s, 'intensity_index') && any(v & ~isnan(s.intensity_index))
        blocks.index_mean(b) = mean(s.intensity_index(v & ~isnan(s.intensity_index)));
    end

    v = s.preimpact_valid;
    blocks.swing_n_valid(b) = sum(v);
    blocks.swing_invalid_reasons{b} = count_codes(split_codes(s.preimpact_flags(s.accepted & ~v)));
    if any(strcmp(r.role, {'reference', 'controlled'}))
        blocks.swing_status{b} = 'stationary_session';
    else
        [blocks.swing_cv_pct(b), blocks.swing_mean_dps(b), blocks.swing_sd_dps(b)] = ...
            vs_cv(s.preimpact_peak_dps(v));
        blocks.swing_status{b} = status(sum(v), min_n);
    end

    if strcmp(r.role, 'controlled') && strcmp(blocks.condition{b}, 'middle')
        target = cfg.evaluation.target_middle_rms_cv_pct;
        if isnan(blocks.rms_cv_pct(b))
            blocks.target_note{b} = 'middle_target_not_assessable';
        elseif blocks.rms_cv_pct(b) <= target
            blocks.target_note{b} = sprintf('middle_rms_cv_at_or_below_%g_pct_target', target);
        else
            blocks.target_note{b} = sprintf('middle_rms_cv_above_%g_pct_target', target);
        end
        if strcmp(blocks.rms_status{b}, 'insufficient')
            blocks.target_note{b} = [blocks.target_note{b} '_insufficient_block'];
        end
    end
end
end

function s = status(n, min_n)
if n >= min_n
    s = 'sufficient';
else
    s = 'insufficient';
end
end

function t = meta_text(meta, key)
t = '';
if isfield(meta, key)
    t = meta.(key);
end
end

function codes = split_codes(flag_strings)
codes = {};
for i = 1:numel(flag_strings)
    if isempty(flag_strings{i})
        codes{end+1} = 'value_missing'; %#ok<AGROW>
    else
        codes = [codes strsplit(flag_strings{i}, ';')]; %#ok<AGROW>
    end
end
end

function s = count_codes(codes)
% 'code:count' pairs in first-seen order, e.g. 'rms_gap:1;rms_clipped:2'.
s = '';
if isempty(codes)
    return
end
u = {};
for i = 1:numel(codes)
    if ~any(strcmp(u, codes{i}))
        u{end+1} = codes{i}; %#ok<AGROW>
    end
end
parts = cell(1, numel(u));
for i = 1:numel(u)
    parts{i} = sprintf('%s:%d', u{i}, sum(strcmp(codes, u{i})));
end
s = strjoin(parts, ';');
end
