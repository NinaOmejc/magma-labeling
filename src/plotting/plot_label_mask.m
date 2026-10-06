function fig = plot_label_mask(label_mask, label_names, config, availability_reason)
% PLOT_LABEL_MASK Render detected label states as a time-by-label raster.
%
% Inputs:
%   label_mask  - Nsample x Nlabel logical matrix on the native sample grid.
%   label_names - Nlabel cell array of canonical short label names.
%   config      - Pipeline settings supplying fs, label metadata, and plot options.
%   availability_reason - Optional per-label reasons; not_computed rows are gray.
%
% Outputs:
%   fig - Figure handle while plotting; empty after save_figure or when disabled.

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
    label_names = validate_canonical_label_order(label_names, n_labels);
    if nargin < 4 || isempty(availability_reason)
        availability_reason = repmat({'available'}, 1, n_labels);
    end
    availability_reason = cellstr(string(availability_reason));
    if numel(availability_reason) ~= n_labels
        error('MAGMA:LabelMask:AvailabilityAlignment', ...
            'availability_reason must contain one value per label.');
    end
    not_computed = strcmp(availability_reason, 'not_computed');
    display_mask = double(label_mask');
    display_mask(not_computed, :) = 2;

    t_sec = (0:n_samples-1) / config.fs;
    row_labels = resolve_row_labels(label_names, config, n_labels);
    fig_height = max(420, 120 + 48 * n_labels);

    fig = figure( ...
        'Units', 'pixels', ...
        'Position', [80 80 1500 fig_height], ...
        'Visible', config.make_figs_visible, ...
        'Color', 'w');

    ax = axes('Parent', fig);
    imagesc(ax, t_sec, 1:n_labels, display_mask);
    if t_sec(end) > 0
        xlim(ax, [0 t_sec(end)]);
    else
        xlim(ax, [0, 1 / max(config.fs, 1)]);
    end
    ylim(ax, [0.5, n_labels + 0.5]);
    set(ax, ...
        'YTick', 1:n_labels, ...
        'YTickLabel', row_labels, ...
        'YDir', 'reverse', ...
        'TickDir', 'out', ...
        'Layer', 'top', ...
        'Box', 'off', ...
        'FontSize', 11);

    xlabel(ax, 'Time (s)');
    ylabel(ax, 'Dysfunction');
    title(ax, sprintf('Detected Dysfunction Mask | Subject %d | Measurement %d', config.subject, config.measure));

    cmap = build_label_mask_colormap(config);
    colormap(ax, cmap);
    caxis(ax, [-0.5 2.5]);

    cb = colorbar(ax);
    cb.Ticks = [0 1 2];
    cb.TickLabels = {'Absent', 'Present', 'Not computed'};
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

    save_figure(config, 'label_mask');
    fig = [];
end

function label_names = validate_canonical_label_order(label_names, n_labels)
% VALIDATE_CANONICAL_LABEL_ORDER Keep mask columns and displayed rows aligned.

    label_names = cellstr(string(label_names));
    label_names = label_names(:)';
    canonical_names = get_labels('short');
    if ~isequal(label_names, canonical_names)
        error('MAGMA:LabelMask:LabelOrder', ...
            'label_names must match get_labels(''short'') in canonical order.');
    end
    if n_labels ~= numel(label_names)
        error('MAGMA:LabelMask:MaskAlignment', ...
            'size(label_mask,2) must equal numel(label_names).');
    end
end

function cmap = build_label_mask_colormap(config)
% BUILD_LABEL_MASK_COLORMAP Resolve absent, present, and not-computed colors.

    binary_colors = [ ...
        1.00 1.00 1.00; ...
        0.78 0.12 0.12];

    if isfield(config, 'LabelMask') && isfield(config.LabelMask, 'binary_colors') && ...
            isnumeric(config.LabelMask.binary_colors) && all(size(config.LabelMask.binary_colors) == [2, 3])
        binary_colors = config.LabelMask.binary_colors;
    end

    cmap = [binary_colors; 0.72 0.72 0.72];
    cmap = min(max(cmap, 0), 1);
end

function row_labels = resolve_row_labels(label_names, config, n_labels)
% RESOLVE_ROW_LABELS Format one display string per label-mask column.
% Canonical short names are optionally paired with their descriptive names;
% unnamed rows receive positional labels up to n_labels.

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
% PRETTIFY_LABEL_TEXT Turn identifiers into space-separated display text.
% Underscores and lower-to-upper camel-case boundaries become spaces.

    text_out = char(string(text_in));
    text_out = strrep(text_out, '_', ' ');
    text_out = regexprep(text_out, '(?<=[a-z])(?=[A-Z])', ' ');
    text_out = regexprep(text_out, '\s+', ' ');
    text_out = strtrim(text_out);
end
