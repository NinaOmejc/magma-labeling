function fig = plot_label_mask(label_mask, label_names, config)
% plot_label_mask
% Plot a label-by-time heatmap for the final label mask.

    fig = [];

    if nargin < 3 || isempty(config) || ~isfield(config, 'LabelMask') || ~config.LabelMask.do_plot
        return;
    end
    if isempty(label_mask)
        return;
    end

    n_samples = size(label_mask, 1);
    n_labels = size(label_mask, 2);
    if n_samples == 0 || n_labels == 0
        return;
    end

    t_sec = (0:n_samples-1) / config.new_fs;
    row_labels = resolve_row_labels(label_names, config, n_labels);
    fig_height = max(420, 120 + 48 * n_labels);

    fig = figure( ...
        'Units', 'pixels', ...
        'Position', [80 80 1500 fig_height], ...
        'Visible', config.make_figs_visible, ...
        'Color', 'w');

    ax = axes('Parent', fig);
    imagesc(ax, t_sec, 1:n_labels, double(label_mask'));
    axis(ax, 'xy');
    if t_sec(end) > 0
        xlim(ax, [0 t_sec(end)]);
    else
        xlim(ax, [0, 1 / max(config.new_fs, 1)]);
    end
    ylim(ax, [0.5, n_labels + 0.5]);
    set(ax, ...
        'YTick', 1:n_labels, ...
        'YTickLabel', row_labels, ...
        'TickDir', 'out', ...
        'Layer', 'top', ...
        'Box', 'off', ...
        'FontSize', 11);

    xlabel(ax, 'Time (s)');
    ylabel(ax, 'Dysfunction');
    title(ax, sprintf('Detected Dysfunction Mask | Subject %d | Measurement %d', config.subject, config.measure));

    cmap = build_label_mask_colormap(config);
    colormap(ax, cmap);
    caxis(ax, [-0.5 1.5]);

    cb = colorbar(ax);
    cb.Ticks = [0 1];
    cb.TickLabels = {'Absent', 'Present'};
    ylabel(cb, 'Label state');

    hold(ax, 'on');
    for y = 1.5:1:(n_labels - 0.5)
        plot(ax, xlim(ax), [y, y], '-', ...
            'Color', [0.45 0.45 0.45], 'LineWidth', 1.0, 'HandleVisibility', 'off');
    end
    hold(ax, 'off');

    ax.XGrid = 'on';
    ax.YGrid = 'off';
    ax.GridAlpha = 0.12;
    ax.MinorGridAlpha = 0.08;

    if config.LabelMask.save_plot
        plot_config = config;
        plot_config.save_plots = true;
        save_figure(plot_config, 'label_mask');
    elseif strcmpi(config.make_figs_visible, 'off')
        close(fig);
        fig = [];
    end
end

function cmap = build_label_mask_colormap(config)
    cmap = [ ...
        1.00 1.00 1.00; ...
        0.78 0.12 0.12];

    if isfield(config, 'LabelMask') && isfield(config.LabelMask, 'binary_colors') && ...
            isnumeric(config.LabelMask.binary_colors) && all(size(config.LabelMask.binary_colors) == [2, 3])
        cmap = config.LabelMask.binary_colors;
    end

    cmap = min(max(cmap, 0), 1);
end

function row_labels = resolve_row_labels(label_names, config, n_labels)
    row_labels = label_names(:);
    if isempty(row_labels)
        row_labels = arrayfun(@(k) sprintf('Label %d', k), 1:n_labels, 'UniformOutput', false);
        return;
    end

    use_long_names = isfield(config, 'LabelMask') && isfield(config.LabelMask, 'use_long_names') && config.LabelMask.use_long_names;
    if ~use_long_names || ~isfield(config, 'labels')
        return;
    end

    short_names = {config.labels.short};
    long_names = {config.labels.long};

    for i = 1:numel(row_labels)
        idx = find(strcmp(short_names, row_labels{i}), 1);
        if ~isempty(idx)
            row_labels{i} = sprintf('%s | %s', short_names{idx}, prettify_label_text(long_names{idx}));
        else
            row_labels{i} = prettify_label_text(row_labels{i});
        end
    end
end

function text_out = prettify_label_text(text_in)
    text_out = char(string(text_in));
    text_out = strrep(text_out, '_', ' ');
    text_out = regexprep(text_out, '(?<=[a-z])(?=[A-Z])', ' ');
    text_out = regexprep(text_out, '\s+', ' ');
    text_out = strtrim(text_out);
end
