function overview = plot_group_diagnostic_overview(config_or_results_path, group_table)
% plot_group_diagnostic_overview
% Descriptive group-level plots for diagnostic traces and label summaries.
%
% This is intended as a first-pass QC/overview, not formal statistics.
% It saves:
%   1) per-measure time-series overlays across subjects,
%   2) per-measure boxplots of each subject's within-recording median,
%   3) per-measure boxplots of within-recording spread (p90 - p10),
%   4) heatmaps and CSV summaries for label fractions and event counts.

    if nargin < 1 || isempty(config_or_results_path)
        config = get_config();
        results_path = config.path_results_out;
        config_or_results_path = config;
    elseif isstruct(config_or_results_path)
        config = config_or_results_path;
        results_path = config.path_results_out;
    else
        config = struct();
        results_path = char(config_or_results_path);
    end

    if nargin < 2 || isempty(group_table)
        group_table = build_group_label_table(config_or_results_path);
    end

    out_dir = fullfile(results_path, 'group_analysis', 'diagnostic_overview');
    if ~isfolder(out_dir)
        mkdir(out_dir);
    end

    specs = default_diagnostic_signal_specs();
    records = result_records_from_table(group_table);

    overview = struct();
    overview.out_dir = out_dir;
    overview.time_series_files = plot_time_series_overlays(records, specs, config, out_dir);
    overview.diagnostic_median_file = plot_diagnostic_boxplots(group_table, specs, config, out_dir, 'median');
    overview.diagnostic_spread_file = plot_diagnostic_boxplots(group_table, specs, config, out_dir, 'spread');
    [overview.label_fraction_file, overview.event_count_file, overview.label_summary_csv] = ...
        plot_label_event_overviews(group_table, config, out_dir);

    diagnostic_summary_cols = diagnostic_summary_columns(group_table, specs);
    overview.diagnostic_summary_csv = write_metric_summary_by_measure(group_table, ...
        diagnostic_summary_cols, fullfile(out_dir, 'group_diagnostic_descriptive_summary.csv'));

    fprintf('Saved group diagnostic overview: %s\n', out_dir);
end

function specs = default_diagnostic_signal_specs()
    specs = struct( ...
        'source', {}, ...
        'field', {}, ...
        'summary_prefix', {}, ...
        'title', {}, ...
        'ylabel', {}, ...
        'file_stub', {});

    specs(end+1) = make_signal_spec('diagnostic_signals', ...
        'breathing_rate_slow_window_bpm_diaph', ...
        'diagnostic_breathing_rate_slow_window_bpm_diaph', ...
        'Breathing rate, diaphragm', 'bpm', 'breathing_rate_diaph');

    specs(end+1) = make_signal_spec('diagnostic_signals', ...
        'irregularity_robust_cov_diaph', ...
        'diagnostic_irregularity_robust_cov_diaph', ...
        'Irregularity robust CoV, diaphragm', 'robust CoV', 'irregularity_robust_cov_diaph');

    specs(end+1) = make_signal_spec('diagnostic_signals', ...
        'breath_amplitude_ratio_to_reference_diaph', ...
        'diagnostic_breath_amplitude_ratio_to_reference_diaph', ...
        'Breath amplitude/reference, diaphragm', 'ratio', 'amplitude_ratio_diaph');

    specs(end+1) = make_signal_spec('diagnostic_signals', ...
        'spo2_percent', ...
        'diagnostic_spo2_percent', ...
        'SpO2', '%', 'spo2_percent');

    specs(end+1) = make_signal_spec('diagnostic_signals', ...
        'resp_asynchrony_phase_coherence_mid', ...
        'diagnostic_resp_asynchrony_phase_coherence_mid', ...
        'Respiratory asynchrony coherence, mid band', 'coherence', 'resp_asynchrony_coherence_mid');

    specs(end+1) = make_signal_spec('baseline.rolling', ...
        'diaph_amp_ref', ...
        'baseline_rolling_diaph_amp_ref', ...
        'Rolling baseline amplitude, diaphragm', 'amplitude reference', 'rolling_baseline_diaph');
end

function spec = make_signal_spec(source, field, summary_prefix, title_text, ylabel_text, file_stub)
    spec = struct( ...
        'source', source, ...
        'field', field, ...
        'summary_prefix', summary_prefix, ...
        'title', title_text, ...
        'ylabel', ylabel_text, ...
        'file_stub', file_stub);
end

function records = result_records_from_table(group_table)
    records = struct('label_file', {}, 'subject', {}, 'measure', {}, 'subject_group', {});
    if isempty(group_table) || height(group_table) == 0 || ...
            ~ismember('label_file', group_table.Properties.VariableNames)
        return;
    end

    label_files = table_text_column(group_table, 'label_file', "");
    subject = table_numeric_column(group_table, 'subject', nan(height(group_table), 1));
    measure = table_numeric_column(group_table, 'measure', nan(height(group_table), 1));
    subject_group = table_text_column(group_table, 'subject_group', "Unknown");

    for i = 1:height(group_table)
        label_file = char(label_files(i));
        if isempty(label_file) || ~isfile(label_file)
            continue;
        end

        records(end+1).label_file = label_file; %#ok<AGROW>
        records(end).subject = subject(i);
        records(end).measure = measure(i);
        records(end).subject_group = char(subject_group(i));
    end
end

function saved_files = plot_time_series_overlays(records, specs, config, out_dir)
    saved_files = {};
    if isempty(records)
        return;
    end

    measures = unique([records.measure]);
    measures = measures(isfinite(measures));
    if isempty(measures)
        return;
    end

    for i = 1:numel(specs)
        fig = make_group_figure(config, [specs(i).title ' over time']);
        ncols = min(2, numel(measures));
        nrows = ceil(numel(measures) / ncols);
        tl = tiledlayout(fig, nrows, ncols, 'TileSpacing', 'compact', 'Padding', 'compact');
        title(tl, [specs(i).title ' over time'], 'Interpreter', 'none');

        has_signal = false;
        for im = 1:numel(measures)
            ax = nexttile(tl);
            measure = measures(im);
            these_records = records([records.measure] == measure);
            has_signal = plot_measure_time_series(ax, these_records, specs(i), config) || has_signal;
            title(ax, sprintf('M%d (n = %d)', measure, numel(these_records)));
            xlabel(ax, 'Time [min]');
            ylabel(ax, specs(i).ylabel, 'Interpreter', 'none');
            grid(ax, 'on');
        end

        if has_signal
            file_path = fullfile(out_dir, ['group_timeseries_' specs(i).file_stub '.png']);
            save_group_figure(fig, file_path, config);
            saved_files{end+1} = file_path; %#ok<AGROW>
        else
            close(fig);
        end
    end
end

function has_signal = plot_measure_time_series(ax, records, spec, config)
    has_signal = false;
    hold(ax, 'on');

    traces = struct('t', {}, 'y', {}, 'subject_group', {});
    for i = 1:numel(records)
        [t, y] = load_record_signal(records(i).label_file, spec);
        if isempty(t) || isempty(y)
            continue;
        end

        traces(end+1).t = t; %#ok<AGROW>
        traces(end).y = y;
        traces(end).subject_group = records(i).subject_group;
    end

    if isempty(traces)
        text(ax, 0.5, 0.5, 'No signal saved', ...
            'Units', 'normalized', 'HorizontalAlignment', 'center');
        return;
    end

    for i = 1:numel(traces)
        [t_plot, y_plot] = thin_trace(traces(i).t, traces(i).y, group_option(config, 'time_series_step_sec', 10));
        plot(ax, t_plot ./ 60, y_plot, ...
            'Color', group_color(traces(i).subject_group, true), ...
            'LineWidth', 0.7);
    end

    [common_t, median_y] = median_trace(traces, group_option(config, 'time_series_step_sec', 10));
    if ~isempty(common_t)
        plot(ax, common_t ./ 60, median_y, 'k-', 'LineWidth', 2.0);
    end

    add_group_legend(ax, traces);
    has_signal = true;
end

function [t, y] = load_record_signal(label_file, spec)
    t = [];
    y = [];

    switch spec.source
        case 'diagnostic_signals'
            loaded = load(label_file, 'diagnostic_signals');
            if ~isfield(loaded, 'diagnostic_signals') || ...
                    ~isfield(loaded.diagnostic_signals, 'time_sec') || ...
                    ~isfield(loaded.diagnostic_signals, spec.field)
                return;
            end
            t = loaded.diagnostic_signals.time_sec(:);
            y = loaded.diagnostic_signals.(spec.field)(:);

        case 'baseline.rolling'
            loaded = load(label_file, 'baseline');
            if ~isfield(loaded, 'baseline') || ~isfield(loaded.baseline, 'rolling') || ...
                    ~isfield(loaded.baseline.rolling, 't_grid') || ...
                    ~isfield(loaded.baseline.rolling, spec.field)
                return;
            end
            t = loaded.baseline.rolling.t_grid(:);
            y = loaded.baseline.rolling.(spec.field)(:);

        otherwise
            return;
    end

    n = min(numel(t), numel(y));
    t = t(1:n);
    y = y(1:n);
    valid = isfinite(t) & isfinite(y);
    t = t(valid);
    y = y(valid);
    [t, idx] = unique(t, 'stable');
    y = y(idx);
end

function [t_plot, y_plot] = thin_trace(t, y, step_sec)
    if numel(t) <= 2 || ~isfinite(step_sec) || step_sec <= 0
        t_plot = t;
        y_plot = y;
        return;
    end

    dt = median(diff(t), 'omitnan');
    if ~isfinite(dt) || dt <= 0
        dt = step_sec;
    end
    stride = max(1, round(step_sec / dt));
    idx = 1:stride:numel(t);
    if idx(end) ~= numel(t)
        idx(end+1) = numel(t);
    end
    t_plot = t(idx);
    y_plot = y(idx);
end

function [common_t, median_y] = median_trace(traces, step_sec)
    common_t = [];
    median_y = [];
    max_t = 0;
    for i = 1:numel(traces)
        if ~isempty(traces(i).t)
            max_t = max(max_t, max(traces(i).t));
        end
    end
    if max_t <= 0
        return;
    end

    common_t = (0:step_sec:max_t)';
    if common_t(end) < max_t
        common_t(end+1) = max_t;
    end

    y_mat = nan(numel(common_t), numel(traces));
    for i = 1:numel(traces)
        valid = isfinite(traces(i).t) & isfinite(traces(i).y);
        if nnz(valid) < 2
            continue;
        end
        y_mat(:, i) = interp1(traces(i).t(valid), traces(i).y(valid), common_t, 'linear', nan);
    end

    median_y = median(y_mat, 2, 'omitnan');
    valid_median = isfinite(median_y);
    common_t = common_t(valid_median);
    median_y = median_y(valid_median);
end

function saved_file = plot_diagnostic_boxplots(group_table, specs, config, out_dir, mode)
    saved_file = '';
    if isempty(group_table) || height(group_table) == 0 || ...
            ~ismember('measure', group_table.Properties.VariableNames)
        return;
    end

    plot_specs = specs_with_available_summary(group_table, specs, mode);
    if isempty(plot_specs)
        return;
    end

    fig = make_group_figure(config, ['Diagnostic ' mode ' boxplots']);
    ncols = min(3, numel(plot_specs));
    nrows = ceil(numel(plot_specs) / ncols);
    tl = tiledlayout(fig, nrows, ncols, 'TileSpacing', 'compact', 'Padding', 'compact');
    if strcmp(mode, 'median')
        title(tl, 'Within-recording medians by measurement');
    else
        title(tl, 'Within-recording spread by measurement (p90 - p10)');
    end

    for i = 1:numel(plot_specs)
        ax = nexttile(tl);
        y = summary_values(group_table, plot_specs(i), mode);
        plot_measure_boxplot(ax, group_table, y, plot_specs(i).ylabel);
        title(ax, plot_specs(i).title, 'Interpreter', 'none');
    end

    saved_file = fullfile(out_dir, ['group_boxplots_diagnostic_' mode '.png']);
    save_group_figure(fig, saved_file, config);
end

function plot_specs = specs_with_available_summary(group_table, specs, mode)
    keep = false(size(specs));
    vars = group_table.Properties.VariableNames;
    for i = 1:numel(specs)
        if strcmp(mode, 'median')
            keep(i) = ismember([specs(i).summary_prefix '_median'], vars);
        else
            keep(i) = ismember([specs(i).summary_prefix '_p90'], vars) && ...
                ismember([specs(i).summary_prefix '_p10'], vars);
        end
    end
    plot_specs = specs(keep);
end

function y = summary_values(group_table, spec, mode)
    if strcmp(mode, 'median')
        y = group_table.([spec.summary_prefix '_median']);
    else
        y = group_table.([spec.summary_prefix '_p90']) - group_table.([spec.summary_prefix '_p10']);
    end
    y = y(:);
end

function plot_measure_boxplot(ax, group_table, y, ylabel_text)
    measure = table_numeric_column(group_table, 'measure', nan(height(group_table), 1));
    subject = table_numeric_column(group_table, 'subject', (1:height(group_table))');
    subject_group = table_text_column(group_table, 'subject_group', "Unknown");

    valid = isfinite(measure) & isfinite(y);
    if ~any(valid)
        text(ax, 0.5, 0.5, 'No finite values', ...
            'Units', 'normalized', 'HorizontalAlignment', 'center');
        return;
    end

    hold(ax, 'on');
    boxchart(ax, measure(valid), y(valid), ...
        'BoxFaceColor', [0.70 0.70 0.70], ...
        'MarkerStyle', 'none');

    x = measure(valid) + deterministic_jitter(subject(valid), 0.12);
    colors = group_colors(subject_group(valid), false);
    scatter(ax, x, y(valid), 22, colors, 'filled', ...
        'MarkerFaceAlpha', 0.80, 'MarkerEdgeColor', [0.20 0.20 0.20], ...
        'MarkerEdgeAlpha', 0.35);

    xlabel(ax, 'Measurement');
    ylabel(ax, ylabel_text, 'Interpreter', 'none');
    grid(ax, 'on');
    add_group_legend(ax, subject_group(valid));
end

function [label_fraction_file, event_count_file, summary_csv] = plot_label_event_overviews(group_table, config, out_dir)
    label_fraction_file = '';
    event_count_file = '';
    summary_csv = '';

    if isempty(group_table) || height(group_table) == 0
        return;
    end

    vars = group_table.Properties.VariableNames;
    label_cols = vars(startsWith(vars, 'label_') & endsWith(vars, '_fraction'));
    event_cols = vars(startsWith(vars, 'events_') & endsWith(vars, '_count'));

    if ~isempty(label_cols)
        label_fraction_file = fullfile(out_dir, 'group_label_fraction_heatmap.png');
        plot_measure_metric_heatmap(group_table, label_cols, ...
            'Median label fraction by measurement', 'Fraction of recording', ...
            label_fraction_file, config);
    end

    if ~isempty(event_cols)
        event_cols = top_metric_columns(group_table, event_cols, 12);
        event_count_file = fullfile(out_dir, 'group_event_count_heatmap.png');
        plot_measure_metric_heatmap(group_table, event_cols, ...
            'Median event count by measurement', 'Event count', ...
            event_count_file, config);
    end

    if ~isempty(label_cols) || ~isempty(event_cols)
        summary_csv = write_metric_summary_by_measure(group_table, [label_cols event_cols], ...
            fullfile(out_dir, 'group_label_event_descriptive_summary.csv'));
    end
end

function plot_measure_metric_heatmap(group_table, metric_cols, title_text, colorbar_text, file_path, config)
    measure = table_numeric_column(group_table, 'measure', nan(height(group_table), 1));
    measures = unique(measure(isfinite(measure)));
    if isempty(measures)
        return;
    end

    values = nan(numel(metric_cols), numel(measures));
    for im = 1:numel(measures)
        in_measure = measure == measures(im);
        for ic = 1:numel(metric_cols)
            x = group_table.(metric_cols{ic});
            x = x(in_measure);
            values(ic, im) = median(x(isfinite(x)), 'omitnan');
        end
    end

    fig = make_group_figure(config, title_text);
    ax = axes(fig);
    imagesc(ax, values);
    colormap(ax, parula);
    cb = colorbar(ax);
    cb.Label.String = colorbar_text;
    cb.Label.Interpreter = 'none';
    set(ax, ...
        'XTick', 1:numel(measures), ...
        'XTickLabel', compose('M%d', measures), ...
        'YTick', 1:numel(metric_cols), ...
        'YTickLabel', friendly_metric_names(metric_cols), ...
        'TickLabelInterpreter', 'none');
    xlabel(ax, 'Measurement');
    title(ax, title_text, 'Interpreter', 'none');
    save_group_figure(fig, file_path, config);
end

function selected_cols = top_metric_columns(group_table, metric_cols, max_cols)
    if numel(metric_cols) <= max_cols
        selected_cols = metric_cols;
        return;
    end

    totals = nan(size(metric_cols));
    for i = 1:numel(metric_cols)
        x = group_table.(metric_cols{i});
        totals(i) = sum(x(isfinite(x)), 'omitnan');
    end
    [~, order] = sort(totals, 'descend');
    selected_cols = metric_cols(order(1:max_cols));
end

function csv_path = write_metric_summary_by_measure(group_table, metric_cols, csv_path)
    if isempty(group_table) || height(group_table) == 0 || isempty(metric_cols) || ...
            ~ismember('measure', group_table.Properties.VariableNames)
        csv_path = '';
        return;
    end

    measure = table_numeric_column(group_table, 'measure', nan(height(group_table), 1));
    measures = unique(measure(isfinite(measure)));
    rows = struct('measure', {}, 'metric', {}, 'n', {}, 'mean', {}, 'median', {}, 'p10', {}, 'p90', {}, 'min', {}, 'max', {});

    for im = 1:numel(measures)
        in_measure = measure == measures(im);
        for ic = 1:numel(metric_cols)
            x = group_table.(metric_cols{ic});
            x = x(in_measure);
            x = x(isfinite(x));

            rows(end+1).measure = measures(im); %#ok<AGROW>
            rows(end).metric = metric_cols{ic};
            rows(end).n = numel(x);
            if isempty(x)
                rows(end).mean = nan;
                rows(end).median = nan;
                rows(end).p10 = nan;
                rows(end).p90 = nan;
                rows(end).min = nan;
                rows(end).max = nan;
            else
                rows(end).mean = mean(x, 'omitnan');
                rows(end).median = median(x, 'omitnan');
                rows(end).p10 = prctile(x, 10);
                rows(end).p90 = prctile(x, 90);
                rows(end).min = min(x);
                rows(end).max = max(x);
            end
        end
    end

    if isempty(rows)
        csv_path = '';
        return;
    end

    summary_table = struct2table(rows);
    writetable(summary_table, csv_path);
end

function cols = diagnostic_summary_columns(group_table, specs)
    cols = {};
    if isempty(group_table)
        return;
    end

    vars = group_table.Properties.VariableNames;
    for i = 1:numel(specs)
        median_col = [specs(i).summary_prefix '_median'];
        p10_col = [specs(i).summary_prefix '_p10'];
        p90_col = [specs(i).summary_prefix '_p90'];
        if ismember(median_col, vars)
            cols{end+1} = median_col; %#ok<AGROW>
        end
        if ismember(p10_col, vars)
            cols{end+1} = p10_col; %#ok<AGROW>
        end
        if ismember(p90_col, vars)
            cols{end+1} = p90_col; %#ok<AGROW>
        end
    end
end

function values = table_numeric_column(T, name, default_values)
    if ismember(name, T.Properties.VariableNames)
        values = T.(name);
        if iscell(values)
            values = cellfun(@double, values);
        end
        values = double(values(:));
    else
        values = default_values(:);
    end
end

function values = table_text_column(T, name, default_value)
    if ismember(name, T.Properties.VariableNames)
        raw = T.(name);
        if iscell(raw)
            values = string(raw);
        elseif iscategorical(raw)
            values = string(raw);
        elseif isstring(raw)
            values = raw;
        elseif ischar(raw)
            values = string(cellstr(raw));
        else
            values = string(raw);
        end
    else
        values = repmat(string(default_value), height(T), 1);
    end

    values = values(:);
    values(ismissing(values) | strlength(values) == 0) = string(default_value);
end

function c = group_color(group_name, faint)
    group_name = lower(char(string(group_name)));
    switch group_name
        case 'control'
            c = [0.00 0.45 0.74];
        case 'patient'
            c = [0.85 0.33 0.10];
        otherwise
            c = [0.45 0.45 0.45];
    end

    if faint
        c = 0.45 .* c + 0.55 .* [1 1 1];
    end
end

function colors = group_colors(group_names, faint)
    group_names = string(group_names);
    colors = nan(numel(group_names), 3);
    for i = 1:numel(group_names)
        colors(i, :) = group_color(group_names(i), faint);
    end
end

function add_group_legend(ax, groups)
    if isstruct(groups) && isfield(groups, 'subject_group')
        groups = string({groups.subject_group});
    else
        groups = string(groups);
    end
    groups = unique(groups(:));
    if isempty(groups) || all(groups == "")
        groups = "Unknown";
    end

    hold(ax, 'on');
    handles = gobjects(0);
    labels = {};
    for i = 1:numel(groups)
        handles(end+1) = plot(ax, nan, nan, '-', ...
            'Color', group_color(groups(i), false), 'LineWidth', 1.5); %#ok<AGROW>
        labels{end+1} = char(groups(i)); %#ok<AGROW>
    end
    handles(end+1) = plot(ax, nan, nan, 'k-', 'LineWidth', 2.0);
    labels{end+1} = 'Median';
    legend(ax, handles, labels, 'Location', 'best', 'Interpreter', 'none');
end

function jitter = deterministic_jitter(subject, width)
    jitter = width .* sin(double(subject(:)) .* 12.9898);
end

function labels = friendly_metric_names(metric_cols)
    labels = string(metric_cols);
    labels = erase(labels, "label_");
    labels = erase(labels, "_fraction");
    labels = erase(labels, "events_");
    labels = erase(labels, "_count");
    labels = replace(labels, "_", " ");
end

function value = group_option(config, name, default_value)
    value = default_value;
    if isfield(config, 'group') && isfield(config.group, name)
        value = config.group.(name);
    elseif isfield(config, name)
        value = config.(name);
    end
    if isempty(value)
        value = default_value;
    end
end

function fig = make_group_figure(config, figure_name)
    fig = figure( ...
        'Units', 'pixels', ...
        'Position', [100 100 1400 850], ...
        'Visible', resolve_visibility(config), ...
        'Color', 'w', ...
        'Name', figure_name);
end

function save_group_figure(fig, file_path, config)
    dpi = 150;
    if isfield(config, 'plot_dpi') && ~isempty(config.plot_dpi)
        dpi = config.plot_dpi;
    end

    exportgraphics(fig, file_path, 'Resolution', dpi);
    close(fig);
end

function visibility = resolve_visibility(config)
    visibility = 'off';
    if isfield(config, 'make_figs_visible') && ~isempty(config.make_figs_visible)
        visibility = char(string(config.make_figs_visible));
    end
end
