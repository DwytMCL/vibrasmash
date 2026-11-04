function file = vs_plot_blocks(blocks, results, out_dir, synthetic)
%VS_PLOT_BLOCKS Individual-shot values and block CVs for every block.
%
%   file = vs_plot_blocks(blocks, results, out_dir, synthetic)
%
%   Writes <out_dir>/blocks.png (proposal: "block-level coefficients of
%   variation for impact RMS and pre-impact peak angular speed, with
%   individual-shot plots"):
%     1. valid impact RMS of every shot, one column per block
%     2. valid pre-impact peak angular speed of every shot (stroke and
%        movement blocks; stationary blocks have no swing)
%     3. the two CVs per block; blocks with fewer than eight valid shots
%        are labelled "insufficient"
%
%   Tests: tests/integration/test_pipeline.m

if isstruct(results)
    results = num2cell(results);
end
nb = numel(blocks.block);
names = blocks.block;
fig = figure('Visible', 'off', 'Position', [100 100 1100 850]);
closer = onCleanup(@() close(fig));

subplot(3, 1, 1);
hold on
for b = 1:nb
    s = results{b}.shots;
    v = s.rms_v(s.rms_valid);
    plot(b + 0.15 * linspace(-1, 1, numel(v)), v, 'o');
end
hold off
set_ticks(nb, names);
xlim([0.5 nb + 0.5]);
ylabel('impact RMS (V)');
t = 'Valid impact RMS per shot';
if synthetic
    t = ['SYNTHETIC TEST DATA - not a measurement. ' t];
end
title(t, 'Interpreter', 'none');

subplot(3, 1, 2);
hold on
for b = 1:nb
    if strcmp(blocks.swing_status{b}, 'stationary_session')
        continue
    end
    s = results{b}.shots;
    v = s.preimpact_peak_dps(s.preimpact_valid);
    plot(b + 0.15 * linspace(-1, 1, numel(v)), v, 's');
end
hold off
set_ticks(nb, names);
xlim([0.5 nb + 0.5]);
ylabel('peak angular speed (deg/s)');
title('Valid pre-impact peak angular speed per shot (stationary blocks omitted)');

subplot(3, 1, 3);
cv = [blocks.rms_cv_pct blocks.swing_cv_pct];
cv_plot = cv;
cv_plot(isnan(cv_plot)) = 0;
% An extra empty group keeps a single block from being read as a vector
% by bar(); it lies outside the axis limits.
bar(1:nb + 1, [cv_plot; 0 0], 'grouped');
hold on
for b = 1:nb
    labels = {};
    if strcmp(blocks.rms_status{b}, 'insufficient')
        labels{end+1} = 'RMS: insufficient'; %#ok<AGROW>
    end
    if strcmp(blocks.swing_status{b}, 'insufficient')
        labels{end+1} = 'swing: insufficient'; %#ok<AGROW>
    end
    if ~isempty(labels)
        text(b, max([cv_plot(b, :) 1]) * 1.05, strjoin(labels, ', '), ...
            'HorizontalAlignment', 'center', 'FontSize', 8);
    end
end
hold off
set_ticks(nb, names);
xlim([0.5 nb + 0.5]);
ylabel('CV (%)');
legend({'impact RMS CV', 'peak angular speed CV'}, 'Location', 'northwest');
title('Block CVs, valid shots only (a missing bar = not computed)');

file = fullfile(out_dir, 'blocks.png');
print(fig, file, '-dpng', '-r90');
end

function set_ticks(nb, names)
set(gca, 'XTick', 1:nb, 'XTickLabel', names);
try
    set(gca, 'TickLabelInterpreter', 'none');   % session ids contain underscores
catch
end
end
