function run = demo_synthetic(out_root, plots, verbose)
%DEMO_SYNTHETIC Run the whole pipeline on labelled SYNTHETIC test sessions.
%
%   run = demo_synthetic()            writes to <project>/results
%   run = demo_synthetic(out_root)
%   run = demo_synthetic(out_root, plots, verbose)   plots: save figures
%                                     (default true); verbose: print each step
%
%   Shows every output of run_vibrasmash before real recordings exist.
%   NOTHING THIS PRODUCES IS A MEASUREMENT: the sessions come from
%   make_synthetic_fixture, the run folder name starts with synthetic_, and
%   every CSV row, plot title and log says SYNTHETIC. Do not report any of
%   its numbers as VibraSmash results.
%
%   Sessions (written to <out_root>/synthetic_demo_fixtures, replaced on
%   each run):
%     reference   10 stationary middle-condition impacts (role reference)
%     controlled  10 stationary middle-condition impacts (role controlled)
%     stroke b1   10 contacts with swings, 2 dry swings, 3 handling bumps
%     stroke b2   the same pattern, different amplitudes and seed
%   Annotations for the two stroke blocks come from the planted events
%   (make_synthetic_annotations).
%
%   The two pilot settings are given TEST values chosen for the synthetic
%   noise (5 mV noise floor, 60 deg/s swing threshold). They are not
%   measurements and must not be copied into the config. The combined
%   piezo + gyro rule is switched on, so handling bumps are rejected shots;
%   the evaluation still reports both rules.

root = fileparts(fileparts(mfilename('fullpath')));   % path set by vs_setup beforehand
if nargin < 1 || isempty(out_root)
    out_root = fullfile(root, 'results');
end
if nargin < 2
    plots = true;
end
if nargin < 3
    verbose = false;
end
tmp = fullfile(out_root, 'synthetic_demo_fixtures');   % kept, so the run log's
if ~exist(tmp, 'dir')                                   % input hashes can be checked
    mkdir(tmp);
end

cfg = default_config();
cfg.detect.noise_floor_threshold = 0.005;       % TEST value, synthetic noise only
cfg.detect.swing_confirm_threshold_dps = 60;    % TEST value, synthetic noise only
cfg.detect.swing_confirm_enabled = true;        % use the combined rule for the shots

ref = stationary('demo_reference', 'reference', 11, [200 210 190 205 195 200 215 185 200 210], tmp);
ctrl = stationary('demo_controlled_middle', 'controlled', 12, ...
    [205 190 200 215 195 185 210 200 190 205], tmp);
b1 = stroke('demo_P01_block1', 13, 1, [220 260 240 200 250 230 270 210 245 235], tmp);
b2 = stroke('demo_P01_block2', 14, 2, [150 300 180 280 200 260 170 290 210 240], tmp);

opts.sessions = {ctrl.folder, b1.folder, b2.folder};
opts.reference = {ref.folder};
opts.annotations = {make_synthetic_annotations(b1.folder), make_synthetic_annotations(b2.folder)};
opts.cfg = cfg;
opts.out_root = out_root;
opts.label = 'demo';
opts.plots = plots;
opts.verbose = verbose;
run = run_vibrasmash(opts);
end

function info = stationary(name, role, seed, amps, out_dir)
spec = make_synthetic_fixture();
spec.name = name;
spec.seed = seed;
spec.out_dir = out_dir;
spec.synthetic_role = role;
spec.meta_extra = struct('condition', 'middle');
spec.duration_s = 0.5 * numel(amps) + 0.5;
ev = spec.events(1);
ev.gyro_peak_dps = 0;
for e = 1:numel(amps)
    ev.t_s = 0.5 * e;
    ev.piezo_amp_mv = amps(e);
    spec.events(e) = ev;
end
spec.events = spec.events(1:numel(amps));
info = make_synthetic_fixture(spec);
end

function info = stroke(name, seed, block, amps, out_dir)
spec = make_synthetic_fixture();
spec.name = name;
spec.seed = seed;
spec.out_dir = out_dir;
spec.synthetic_role = 'stroke';
spec.meta_extra = struct('participant', 'P01', 'block', block);
template = spec.events(1);
k = 0;
t = 0.5;
for e = 1:numel(amps)
    k = k + 1;
    ev = template;
    ev.t_s = t;
    ev.piezo_amp_mv = amps(e);
    ev.gyro_peak_dps = 110 + 4 * mod(e * 7, 9);
    events(k) = ev; %#ok<AGROW>
    t = t + 0.5;
    if any(e == [3 6 9])                       % a handling bump: burst, no swing
        k = k + 1;
        ev = template;
        ev.category = 'handling';
        ev.t_s = t;
        ev.piezo_amp_mv = 40;
        ev.piezo_freq_hz = 240;
        ev.gyro_peak_dps = 0;
        events(k) = ev; %#ok<AGROW>
        t = t + 0.5;
    end
    if any(e == [4 8])                         % a dry swing: swing, no burst
        k = k + 1;
        ev = template;
        ev.category = 'dry_swing';
        ev.t_s = t;
        ev.piezo_amp_mv = 0;
        ev.gyro_peak_dps = 140;
        events(k) = ev; %#ok<AGROW>
        t = t + 0.5;
    end
end
spec.events = events;
spec.duration_s = t;
info = make_synthetic_fixture(spec);
end
