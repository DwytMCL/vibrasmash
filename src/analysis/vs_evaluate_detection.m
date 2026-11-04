function ev = vs_evaluate_detection(results, ann, cfg)
%VS_EVALUATE_DETECTION Precision, recall and F1 against annotated actions.
%
%   ev = vs_evaluate_detection(results, ann, cfg)
%
%   results  cell array of session results (vs_process_session)
%   ann      annotations (vs_read_annotations)
%
%   Implements docs/settings_provenance.md, section 4, for both detectors
%   on the same trials (proposal): 'piezo_only' (every detection) and
%   'imu_confirmed' (detections the gyro rule confirmed; stationary
%   sessions bypass it). With tolerance tau = cfg.evaluation.match_tolerance_s:
%     1. a detection at d is a candidate for action a when
%        a.t_start - tau <= d <= a.t_end + tau; the distance is 0 inside the
%        interval, else the distance to the nearer edge
%     2. each detection belongs to its nearest candidate action; a tie
%        between two actions is 'ambiguous' (a false positive, listed)
%     3. contact-detection pairs are assigned one-to-one in order of
%        distance, then detection time
%     4. TP = matched contacts, FN = unmatched contacts (including contacts
%        in sessions with no recording), FP = every other detection, with a
%        reason: in_dry_swing, in_handling, in_frame_tap, duplicate,
%        spurious or ambiguous
%     5. a non-contact action with no detection is a correct rejection,
%        reported per category, outside precision, recall and F1
%     6. precision = TP/(TP+FP), recall = TP/(TP+FN), F1 = 2PR/(P+R); an
%        undefined ratio is NaN and reported as undefined
%
%   Only evaluation data is accepted: every real session needs
%   split = evaluation in meta.txt and in the annotation file. Synthetic
%   test sessions (split = test) are accepted so the code can be tested;
%   the output is then labelled synthetic. Every annotated session must
%   either have a result or be counted as unrecorded; a result with no
%   annotations is an error. Targets (precision and recall >= 0.90) are
%   reported against, never used to tune.
%
%   Tests: tests/unit/test_analysis.m

if isstruct(results)
    results = num2cell(results);
end
tau = cfg.evaluation.match_tolerance_s;
ev.tolerance_s = tau;
ev.warnings = {};
ev.synthetic = false;

% ---- Which sessions, and are they evaluation data?
rec_ids = cellfun(@(r) r.meta.session_id, results, 'UniformOutput', false);
ann_ids = unique(ann.session);
for k = 1:numel(results)
    r = results{k};
    sid = rec_ids{k};
    if ~any(strcmp(ann_ids, sid))
        error('vs_evaluate_detection:unannotated', 'Session %s has no annotations', sid);
    end
    rows = strcmp(ann.session, sid);
    if r.synthetic
        ev.synthetic = true;
        ok_split = {'test', 'evaluation'};
    else
        ok_split = {'evaluation'};
        if ~strcmp(r.meta.split, 'evaluation')
            error('vs_evaluate_detection:split', ['Session %s has split = %s; only ' ...
                'evaluation data may be scored (pilot and tuning data are kept separate)'], ...
                sid, r.meta.split);
        end
    end
    if ~all(ismember(ann.split(rows), ok_split))
        error('vs_evaluate_detection:split', 'Annotations for %s are not marked evaluation', sid);
    end
end
for k = 1:numel(ann_ids)
    if ~any(strcmp(rec_ids, ann_ids{k}))
        rows = strcmp(ann.session, ann_ids{k});
        if ~all(strcmp(ann.split(rows), 'evaluation'))
            error('vs_evaluate_detection:split', 'Annotations for %s are not marked evaluation', ...
                ann_ids{k});
        end
        ev.warnings{end+1} = sprintf(['Session %s is annotated but has no recording: its %d ' ...
            'contact(s) count as missed'], ann_ids{k}, sum(rows & strcmp(ann.category, 'contact')));
    end
end

% ---- Tolerance check: tau should not reach a neighbouring action
for k = 1:numel(ann_ids)
    i = find(strcmp(ann.session, ann_ids{k}));
    [ts, o] = sort(ann.t_start_s(i));
    te = ann.t_end_s(i(o));
    gaps = ts(2:end) - te(1:end-1);
    if ~isempty(gaps) && tau > min(gaps) / 2
        ev.warnings{end+1} = sprintf(['Tolerance %.3f s exceeds half the smallest gap ' ...
            '(%.3f s) between actions in session %s'], tau, min(gaps), ann_ids{k});
    end
end

% ---- Per-session QC, so rejected records cannot disappear (proposal)
ev.qc.session = rec_ids(:);
ev.qc.qc_status = cellfun(@(r) r.qc.status, results(:), 'UniformOutput', false);
ev.qc.piezo_missing_pct = cellfun(@(r) r.qc.piezo.missing_pct, results(:));
ev.qc.imu_missing_pct = cellfun(@(r) r.qc.imu.missing_pct, results(:));
ev.qc.piezo_clipped_pct = cellfun(@(r) r.qc.piezo.clipped_pct, results(:));
ev.qc.imu_gyro_clipped_samples = cellfun(@(r) r.qc.imu.n_gyro_clipped, results(:));
ev.qc.flags = cellfun(@(r) strjoin(r.qc.flags, ';'), results(:), 'UniformOutput', false);

% ---- Score both rules
rules = {'piezo_only', 'imu_confirmed'};
ev.detections = empty_detections();
ev.actions = empty_actions();
for q = 1:numel(rules)
    [rule, dets, acts] = score_rule(rules{q}, results, rec_ids, ann, tau, cfg);
    ev.rules(q) = rule;
    ev.detections = append(ev.detections, dets);
    ev.actions = append(ev.actions, acts);
end
ev.label = '';
if ev.synthetic
    ev.label = 'SYNTHETIC TEST DATA: not an evaluation result';
end
end

% -------------------------------------------------------------------------

function [rule, D, A] = score_rule(name, results, rec_ids, ann, tau, cfg)
rule.name = name;
rule.evaluated = true;
% Collect detections
d_session = {};
d_t = [];
for k = 1:numel(results)
    r = results{k};
    keep = true(numel(r.det.onset_t_us), 1);
    if strcmp(name, 'imu_confirmed')
        stationary = any(strcmp(r.role, {'reference', 'controlled'}));
        if ~stationary
            if ~r.det.swing_evaluated
                rule.evaluated = false;
            end
            keep = r.det.swing_confirmed(:);
        end
    end
    d_t = [d_t; r.det.onset_t_us(keep) / 1e6]; %#ok<AGROW>
    d_session = [d_session; repmat(rec_ids(k), sum(keep), 1)]; %#ok<AGROW>
end
nd = numel(d_t);
na = numel(ann.action_id);

% Home action of each detection (nearest candidate within tau)
home = nan(nd, 1);
dist = nan(nd, 1);
ambiguous = false(nd, 1);
for i = 1:nd
    a = find(strcmp(ann.session, d_session{i}));
    dd = max([ann.t_start_s(a) - d_t(i), d_t(i) - ann.t_end_s(a), zeros(numel(a), 1)], [], 2);
    cand = dd <= tau;
    if ~any(cand)
        continue
    end
    m = min(dd(cand));
    best = a(cand & dd == m);
    if numel(best) > 1
        ambiguous(i) = true;
    else
        home(i) = best;
        dist(i) = m;
    end
end

% One-to-one assignment of contacts
is_contact = strcmp(ann.category, 'contact');
pairs = find(~isnan(home));
pairs = pairs(is_contact(home(pairs)));
[~, o] = sortrows([dist(pairs) d_t(pairs)]);
pairs = pairs(o);
matched_det = false(nd, 1);
matched_act = zeros(na, 1);          % detection index matched to each action
for i = pairs.'
    if matched_act(home(i)) == 0
        matched_act(home(i)) = i;
        matched_det(i) = true;
    end
end

% Detection outcomes
D = empty_detections();
for i = 1:nd
    D.rule{end+1, 1} = name;
    D.session{end+1, 1} = d_session{i};
    D.t_s(end+1, 1) = d_t(i);
    if matched_det(i)
        D.outcome{end+1, 1} = 'TP';
        D.action_id(end+1, 1) = ann.action_id(home(i));
        D.reason{end+1, 1} = '';
    else
        D.outcome{end+1, 1} = 'FP';
        if ambiguous(i)
            D.action_id(end+1, 1) = NaN;
            D.reason{end+1, 1} = 'ambiguous';
        elseif isnan(home(i))
            D.action_id(end+1, 1) = NaN;
            D.reason{end+1, 1} = 'spurious';
        else
            D.action_id(end+1, 1) = ann.action_id(home(i));
            if is_contact(home(i))
                D.reason{end+1, 1} = 'duplicate';
            else
                D.reason{end+1, 1} = ['in_' ann.category{home(i)}];
            end
        end
    end
end

% Action outcomes
A = empty_actions();
for a = 1:na
    A.rule{end+1, 1} = name;
    A.action_id(end+1, 1) = ann.action_id(a);
    A.session{end+1, 1} = ann.session{a};
    A.category{end+1, 1} = ann.category{a};
    hits = find(home == a);
    if is_contact(a)
        if matched_act(a) > 0
            A.outcome{end+1, 1} = 'TP';
            A.detection_t_s(end+1, 1) = d_t(matched_act(a));
        else
            A.outcome{end+1, 1} = 'FN';
            A.detection_t_s(end+1, 1) = NaN;
        end
    elseif isempty(hits)
        A.outcome{end+1, 1} = 'correct_rejection';
        A.detection_t_s(end+1, 1) = NaN;
    else
        A.outcome{end+1, 1} = 'detected';
        A.detection_t_s(end+1, 1) = d_t(hits(1));
    end
end

rule.tp = sum(matched_det);
rule.fp = nd - rule.tp;
rule.fn = sum(is_contact) - rule.tp;
rule.n_contacts = sum(is_contact);
rule.n_detections = nd;
rule.n_ambiguous = sum(ambiguous);
rule.precision = ratio(rule.tp, rule.tp + rule.fp);
rule.recall = ratio(rule.tp, rule.tp + rule.fn);
if isnan(rule.precision) || isnan(rule.recall) || rule.precision + rule.recall == 0
    rule.f1 = NaN;
else
    rule.f1 = 2 * rule.precision * rule.recall / (rule.precision + rule.recall);
end
fp_reasons = D.reason(strcmp(D.outcome, 'FP'));
for c = {'in_dry_swing', 'in_handling', 'in_frame_tap', 'duplicate', 'spurious', 'ambiguous'}
    rule.(['fp_' c{1}]) = sum(strcmp(fp_reasons, c{1}));
end
for c = {'dry_swing', 'handling', 'frame_tap'}
    rows = strcmp(A.category, c{1});
    rule.([c{1} '_actions']) = sum(rows);
    rule.([c{1} '_correct_rejections']) = sum(rows & strcmp(A.outcome, 'correct_rejection'));
end
rule.meets_precision_target = rule.precision >= cfg.evaluation.target_precision;
rule.meets_recall_target = rule.recall >= cfg.evaluation.target_recall;
if ~rule.evaluated
    rule.note = 'gyro rule not evaluated: detect.swing_confirm_threshold_dps is not set';
else
    rule.note = '';
end
end

function r = ratio(a, b)
if b == 0
    r = NaN;
else
    r = a / b;
end
end

function D = empty_detections()
D.rule = {};
D.session = {};
D.t_s = [];
D.outcome = {};
D.action_id = [];
D.reason = {};
D = columns(D);
end

function A = empty_actions()
A.rule = {};
A.action_id = [];
A.session = {};
A.category = {};
A.outcome = {};
A.detection_t_s = [];
A = columns(A);
end

function S = columns(S)
f = fieldnames(S);
for i = 1:numel(f)
    S.(f{i}) = reshape(S.(f{i}), 0, 1);
end
end

function S = append(S, T)
f = fieldnames(S);
for i = 1:numel(f)
    S.(f{i}) = [S.(f{i}); T.(f{i})];
end
end
