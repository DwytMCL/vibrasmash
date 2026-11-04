function tests = test_default_config
%TEST_DEFAULT_CONFIG Unit tests for config/default_config.m.
tests = functiontests(localfunctions);
end

function setupOnce(~)
vs_setup();
end

function testReturnsStructWithProvenance(~)
cfg = default_config();
assert(isstruct(cfg));
assert(size(cfg.provenance, 2) == 4);
end

function testEverySettingHasKnownSourceAndNote(~)
cfg = default_config();
S = cfg.provenance;
for i = 1:size(S, 1)
    assert(any(strcmp(S{i,3}, {'proposal', 'provisional', 'pilot'})), ...
        'Unknown source for %s', S{i,1});
    assert(~isempty(S{i,4}), 'Missing note for %s', S{i,1});
end
end

function testSettingPathsAreUnique(~)
cfg = default_config();
S = cfg.provenance;
assert(numel(unique(S(:,1))) == size(S, 1));
end

function testPilotSettingsAreEmptyUntilMeasured(~)
cfg = default_config();
S = cfg.provenance;
for i = find(strcmp(S(:,3), 'pilot')).'
    assert(isempty(S{i,2}), '%s must stay empty until measured', S{i,1});
end
end

function testProposalValuesArePinned(~)
% A silent change to the study described in the proposal fails here.
c = default_config();
assert(c.sampling.piezo_fs_nominal_hz == 20000);
assert(c.sampling.imu_fs_nominal_hz == 200);
assert(isequal([c.filter.piezo_hp_cutoff_hz, c.filter.piezo_hp_order], [80 4]));
assert(isequal([c.filter.piezo_lp_cutoff_hz, c.filter.piezo_lp_order], [2000 4]));
assert(isequal([c.filter.gyro_lp_cutoff_hz, c.filter.gyro_lp_order], [20 4]));
assert(c.filter.zero_phase == true);
assert(c.detect.envelope_window_s == 0.005);
assert(c.detect.threshold_mad_multiplier == 6);
assert(c.detect.refractory_s == 0.150);
assert(c.features.rms_window_s == 0.100);
assert(c.features.reference_impact_count == 10);
assert(c.features.intensity_scale == 100);
assert(c.features.preimpact_window_s == 0.250);
assert(c.spectrum.nfft == 2048);
assert(strcmp(c.spectrum.window, 'hann'));
assert(c.consistency.min_valid_shots == 8);
assert(isequal([c.evaluation.target_precision, c.evaluation.target_recall], [0.9 0.9]));
assert(c.evaluation.target_middle_rms_cv_pct == 15);
end

function testFftGeometryMatchesProposal(~)
% Proposal: 2,048 samples at 20 kHz = 102.4 ms, bin spacing about 9.77 Hz.
c = default_config();
assert(abs(c.spectrum.nfft / c.sampling.piezo_fs_nominal_hz - 0.1024) < 1e-12);
assert(abs(c.sampling.piezo_fs_nominal_hz / c.spectrum.nfft - 9.765625) < 1e-12);
end
