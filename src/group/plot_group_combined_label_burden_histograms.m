function path = plot_group_combined_label_burden_histograms(config, data)
% PLOT_GROUP_COMBINED_LABEL_BURDEN_HISTOGRAMS Compare both groups in one figure.
% Reuse the split bin tables so every bar matches the separate histograms.

    path = '';
    if ~strcmp(data.layer, 'automatic'), return; end

    groups = {'Control', 'Patient'};
    group_names = {'Healthy controls', 'Patients'};
    edges = 0:5:100;
    centers = (edges(1:end-1) + edges(2:end)) / 2;
    nb = numel(centers);
    nm = numel(data.measures);
    nl = numel(data.labels);
    percentages = zeros(nb, 2*nm, nl);
    series_names = strings(1, 2*nm);
    colors = zeros(2*nm, 3);
    control_colors = [0.08 0.30 0.62; 0.18 0.65 0.88];
    patient_colors = [0.94 0.46 0.12; 0.73 0.12 0.15];
    shades = linspace(0, 1, nm);

    for g = 1:2
        bins = data.histogram_bins(data.histogram_bins.cohort == string(groups{g}), :);
        if g == 1
            endpoints = control_colors;
        else
            endpoints = patient_colors;
        end
        for m = 1:nm
            series = (g-1)*nm + m;
            series_names(series) = sprintf('%s M%d', group_names{g}, ...
                data.measures(m));
            colors(series, :) = (1-shades(m))*endpoints(1, :) + ...
                shades(m)*endpoints(2, :);
            for l = 1:nl
                selected = bins.measurement == data.measures(m) & ...
                    string(bins.label) == string(data.labels{l});
                rows = find(selected);
                [lower, order] = sort(bins.lower_percent(rows));
                rows = rows(order);
                if numel(rows) ~= nb || any(abs(lower - edges(1:end-1)') > 1e-9) || ...
                        any(abs(bins.upper_percent(rows) - edges(2:end)') > 1e-9)
                    error('MAGMA:Group:HistogramBins', ...
                        'Missing or inconsistent bins for %s M%d, %s.', ...
                        groups{g}, data.measures(m), data.labels{l});
                end
                % Each group/measurement has its own assessable denominator.
                counts = bins.subject_n(rows);
                percentages(:, series, l) = 100 .* counts ./ max(sum(counts), 1);
            end
        end
    end

    visible = 'off';
    if isfield(config, 'make_figs_visible') && ~isempty(config.make_figs_visible)
        visible = char(string(config.make_figs_visible));
    end
    ncols = 3;
    nrows = ceil(nl/ncols);
    fig = figure('Visible', visible, 'Color', 'w', ...
        'Position', [60 60 1550 320*nrows]);
    tl = tiledlayout(fig, nrows, ncols, ...
        'TileSpacing', 'compact', 'Padding', 'compact');
    title(tl, ['Label burden distributions (healthy controls and patients, ' ...
        data.layer '; assessed zeros included, unavailable subjects omitted)'], ...
        'Interpreter', 'none');
    for l = 1:nl
        ax = nexttile(tl);
        bars = bar(ax, centers, percentages(:, :, l), 1, 'grouped');
        for series = 1:2*nm
            bars(series).FaceColor = colors(series, :);
        end
        set(ax, 'XLim', [0 100], 'XTick', [0 25 50 75 100]);
        title(ax, data.labels{l}, 'Interpreter', 'none');
        xlabel(ax, '% of assessable time');
        ylabel(ax, '% of group');
        grid(ax, 'on');
        if l == 1
            legend(ax, bars, cellstr(series_names), 'Location', 'northeast');
        end
    end
    path = group_descriptive_plot_path(config, data.out_dir, ...
        ['group_label_burden_histograms_' data.layer '_Control_Patient']);
    save_figure(config, 'group_label_burden_histograms', false, path);
end
