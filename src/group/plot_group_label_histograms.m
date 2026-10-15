function outputs = plot_group_label_histograms(config, data)
% PLOT_GROUP_LABEL_HISTOGRAMS Show automatic label burden distributions.
% A positive label means an available fraction greater than zero. Assessed
% zeros appear in the first burden bin but not in the positive-subject count.

    outputs = struct('distribution_figure', '', 'counts', table(), 'bins', table());
    if ~strcmp(data.layer, 'automatic'), return; end
    if isempty(data.subjects) || isempty(data.measures), return; end
    [suffix, cohort_name] = histogram_scope(data);
    nl = numel(data.labels);
    nm = numel(data.measures);
    positive = zeros(nl, nm);
    count_rows = cell(nl*nm, 6);
    edges = 0:5:100;
    centers = (edges(1:end-1)+edges(2:end))/2;
    bin_counts = zeros(numel(centers), nm, nl);
    bin_rows = cell(nl*nm*numel(centers), 5);
    cr = 0;
    br = 0;
    for l = 1:nl
        for m = 1:nm
            available = data.label_available(:, l, m) & ...
                isfinite(data.label_values(:, l, m));
            values = 100 .* data.label_values(available, l, m);
            positive(l, m) = nnz(values > 0);
            cr = cr + 1;
            count_rows(cr, :) = {data.measures(m), string(data.labels{l}), ...
                numel(data.subjects), nnz(available), ...
                nnz(values == 0), positive(l, m)};
            bin_counts(:, m, l) = histcounts(values, edges)';
            for b = 1:numel(centers)
                br = br + 1;
                bin_rows(br, :) = {data.measures(m), string(data.labels{l}), ...
                    edges(b), edges(b+1), bin_counts(b, m, l)};
            end
        end
    end
    count_table = cell2table(count_rows, 'VariableNames', ...
        {'measurement', 'label', 'subject_n', 'assessable_n', ...
        'assessed_zero_n', 'positive_n'});
    bin_table = cell2table(bin_rows, 'VariableNames', ...
        {'measurement', 'label', 'lower_percent', 'upper_percent', ...
        'subject_n'});
    cohort = repmat("All", height(count_table), 1);
    bin_cohort = repmat("All", height(bin_table), 1);
    if isfield(data, 'histogram_group')
        cohort(:) = string(data.histogram_group);
        bin_cohort(:) = string(data.histogram_group);
    end
    outputs.counts = addvars(count_table, cohort, 'Before', 1);
    outputs.bins = addvars(bin_table, bin_cohort, 'Before', 1, ...
        'NewVariableNames', 'cohort');

    % Normalize each label/measurement within its assessable cohort.
    bin_percentages = 100 .* bin_counts ./ max(sum(bin_counts, 1), 1);

    visible = figure_visibility(config);
    colors = lines(nm);
    ncols = 3;
    nrows = ceil(nl/ncols);
    fig = figure('Visible', visible, 'Color', 'w', ...
        'Position', [60 60 1550 320*nrows]);
    tl = tiledlayout(fig, nrows, ncols, ...
        'TileSpacing', 'compact', 'Padding', 'compact');
    title(tl, ['Label burden distributions (' cohort_name ', ' data.layer ...
        '; assessed zeros included, unavailable subjects omitted)'], ...
        'Interpreter', 'none');
    for l = 1:nl
        ax = nexttile(tl);
        bars = bar(ax, centers, bin_percentages(:, :, l), 1, 'grouped');
        for m = 1:nm, bars(m).FaceColor = colors(m, :); end
        set(ax, 'XLim', [0 100], 'XTick', [0 25 50 75 100]);
        title(ax, data.labels{l}, 'Interpreter', 'none');
        xlabel(ax, '% of assessable time');
        ylabel(ax, '% of group');
        grid(ax, 'on');
        if l == 1
            legend(ax, compose('M%d', data.measures), 'Location', 'northeast');
        end
    end
    outputs.distribution_figure = group_descriptive_plot_path(config, ...
        data.out_dir, ['group_label_burden_histograms_' data.layer suffix]);
    save_figure(config, 'group_label_burden_histograms', false, ...
        outputs.distribution_figure);
end

function [suffix, cohort_name] = histogram_scope(data)
    suffix = '';
    cohort_name = 'All subjects';
    if ~isfield(data, 'histogram_group') || isempty(data.histogram_group)
        return;
    end
    group = char(string(data.histogram_group));
    suffix = ['_' group];
    if strcmp(group, 'Control'), cohort_name = 'Healthy controls'; end
    if strcmp(group, 'Patient'), cohort_name = 'Patients'; end
end

function visible = figure_visibility(config)
    visible = 'off';
    if isfield(config, 'make_figs_visible') && ~isempty(config.make_figs_visible)
        visible = char(string(config.make_figs_visible));
    end
end

