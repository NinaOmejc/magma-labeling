function fig = plot_label_mask(label_mask, label_names, config, availability_reason, events, automatic_mask, automatic_events)
% PLOT_LABEL_MASK Render detected label states as a time-by-label raster.
%
% Inputs:
%   label_mask  - Nsample x Nlabel logical matrix on the native sample grid.
%   label_names - Nlabel cell array of canonical short label names.
%   config      - Pipeline settings supplying fs, label metadata, and plot options.
%   availability_reason - Original detector availability, independent of review.
%   config.LabelMask.review_coverage - Optional explicit Nsample x Nlabel coverage.
%   config.LabelMask.assessable_mask - Optional native-sample physiological support.
%   config.LabelMask.artifact_context - Saved current artifact state/cycles.
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
    sigh_row = find(strcmp(label_names, 'sigh'), 1);
    discrete_sigh = nargin >= 5;
    if discrete_sigh
        display_mask(sigh_row, :) = 0;
    end
    reviewed_plot = isfield(config.LabelMask, 'review_coverage');
    context = struct();
    if isfield(config,'respiratory_artifact_state'), context.respiratory_artifact_state = config.respiratory_artifact_state; end
    if isfield(config.LabelMask,'artifact_context'), context = config.LabelMask.artifact_context; end
    [artifact_qc,artifacts] = respiratory_artifact_qc(context,n_samples,config.fs);
    assessable = true(size(label_mask));
    if isfield(config.LabelMask,'assessable_mask')
        if ~isequal(size(config.LabelMask.assessable_mask),size(label_mask))
            error('MAGMA:LabelMask:AssessabilityAlignment','assessable_mask must align with label_mask.');
        end
        assessable = logical(config.LabelMask.assessable_mask);
    end
    respiratory_rows = ~strcmp(label_names,'desat');
    ranges = artifacts.artifact_intervals_idx;
    for i = 1:size(ranges,1), assessable(ranges(i,1):ranges(i,2),respiratory_rows) = false; end
    if reviewed_plot
        if ~isequal(size(config.LabelMask.review_coverage), size(label_mask))
            error('MAGMA:LabelMask:CoverageAlignment', ...
                'review_coverage must align with label_mask.');
        end
        % Zeros outside explicit coverage are unknown, never accepted negatives.
        display_mask(~logical(config.LabelMask.review_coverage')) = 2;
        unassessable = repmat(~ismember(availability_reason(:), ...
            {'available', 'unreviewed', 'not_computed'}), 1, n_samples);
        unassessable = unassessable | ~assessable';
        display_mask(unassessable) = 4;
        % Computation status comes from the detector metadata and takes precedence.
        display_mask(not_computed, :) = 3;
    else
        unavailable = ~ismember(availability_reason,{'available','unreviewed','not_computed'});
        assessable(:,unavailable) = false;
        display_mask(~assessable') = 3;
        display_mask(not_computed, :) = 2;
    end

    t_sec = (0:n_samples-1) / config.fs;
    row_labels = resolve_row_labels(label_names, config, n_labels);
    fig_height = max(455, 155 + 48 * n_labels);

    fig = figure( ...
        'Units', 'pixels', ...
        'Position', [80 80 1500 fig_height], ...
        'Visible', config.make_figs_visible, ...
        'Color', 'w');
    if isfield(config, 'fig_width') && isfield(config, 'fig_height')
        fig.Position(3:4) = [config.fig_width config.fig_height];
    end

    ax = axes('Parent', fig);
    imagesc(ax, t_sec, 1:n_labels, display_mask);
    if t_sec(end) > 0
        xlim(ax, [0 t_sec(end)]);
    else
        xlim(ax, [0, 1 / max(config.fs, 1)]);
    end
    artifact_y = n_labels + 0.95;
    ylim(ax, [0.5, n_labels + 1.35]);
    set(ax, ...
        'YTick', [1:n_labels artifact_y], ...
        'YTickLabel', [row_labels; {'Respiratory artifact'}], ...
        'YDir', 'reverse', ...
        'TickDir', 'out', ...
        'Layer', 'top', ...
        'Box', 'off', ...
        'FontSize', 11);
    % Fixed recording-time locations preserve absolute ticks when zooming.
    set(ax, 'XTick', 0:200:t_sec(end), 'XMinorTick', 'on');
    ax.XAxis.MinorTickValues = setdiff(50:50:t_sec(end), ax.XTick);

    xlabel(ax, 'Time (s)');
    ylabel(ax, 'Dysfunction');
    heading = 'Detected Dysfunction Mask';
    base_name = 'label_mask';
    if isfield(config.LabelMask, 'title'), heading = config.LabelMask.title; end
    if isfield(config.LabelMask, 'basename'), base_name = config.LabelMask.basename; end
    title(ax, sprintf('%s | Subject %d | Measurement %d', heading, config.subject, config.measure));

    cmap = build_label_mask_colormap(config);
    state_labels = {'Absent', 'Present', 'Not computed'};
    if ~reviewed_plot && any(display_mask(:) == 3)
        cmap(end+1,:) = [0.94 0.83 0.60];
        state_labels{end+1} = 'Unassessable';
    end
    if reviewed_plot
        cmap = [1 1 1; 0.78 0.12 0.12; 0.88 0.88 0.88; 0.35 0.35 0.35];
        state_labels = {'Reviewed negative', 'Reviewed positive', 'Unreviewed', 'Not computed'};
        if any(display_mask(:) == 4)
            cmap(end+1, :) = [0.94 0.83 0.60];
            state_labels{end+1} = 'Unassessable';
        end
    end
    colormap(ax, cmap);
    ax.CLim = [-0.5 size(cmap, 1)-0.5];

    cb = colorbar(ax);
    cb.Ticks = 0:size(cmap, 1)-1;
    cb.TickLabels = state_labels;
    cb.FontSize = 10;
    ylabel(cb, 'Label state');

    hold(ax, 'on');
    automatic_color = [0.15 0.35 0.75];
    legend_handles = gobjects(0);
    legend_labels = {};
    if nargin >= 6 && ~isempty(automatic_mask)
        for row = 1:n_labels
            if row == sigh_row || not_computed(row), continue; end
            change = diff([false; logical(automatic_mask(:, row)); false]);
            first = find(change == 1); last = find(change == -1)-1;
            for i = 1:numel(first)
                rectangle(ax, 'Position', [(first(i)-1)/config.fs, row-0.32, ...
                    (last(i)-first(i)+1)/config.fs, 0.64], ...
                    'FaceColor', 'none', 'EdgeColor', automatic_color, ...
                    'LineStyle', '--', 'LineWidth', 1.6, ...
                    'HandleVisibility', 'off', 'Tag', 'AutomaticDetectionOutline');
            end
        end
        legend_handles(end+1) = plot(ax, nan, nan, '--', ...
            'Color', automatic_color, 'LineWidth', 1.6);
        legend_labels{end+1} = 'Automatic detection (blue dashed outline)';
    end
    if discrete_sigh
        allowed_samples = ~not_computed(sigh_row) & assessable(:,sigh_row)';
        if reviewed_plot
            allowed_samples = display_mask(sigh_row, :) < 2;
        end
        draw_sigh_event_markers(ax, events, sigh_row, cmap(2, :), true, ...
            config.fs, allowed_samples, 5);
        legend_handles(end+1) = plot(ax, nan, nan, 'o', 'LineStyle', 'none', ...
            'MarkerSize', 5, 'MarkerEdgeColor', cmap(2, :), 'MarkerFaceColor', cmap(2, :));
        legend_labels{end+1} = 'Automatic sigh (filled red dot)';
        if reviewed_plot
            legend_labels{end} = 'Reviewed sigh (filled red dot)';
        end
        if nargin >= 7
            if reviewed_plot
                allowed_samples = display_mask(sigh_row, :) ~= 3 & display_mask(sigh_row, :) ~= 4;
            end
            % A larger hollow marker stays visible around an overlapping red dot.
            draw_sigh_event_markers(ax, automatic_events, sigh_row, automatic_color, ...
                false, config.fs, allowed_samples, 8);
            legend_handles(end+1) = plot(ax, nan, nan, 'o', 'LineStyle', 'none', ...
                'MarkerSize', 8, 'MarkerEdgeColor', automatic_color, ...
                'MarkerFaceColor', 'none', 'LineWidth', 1.4);
            legend_labels{end+1} = 'Automatic sigh (hollow blue dot)';
        end
    end
    for y = 1.5:1:(n_labels - 0.5)
        plot(ax, xlim(ax), [y, y], '-', ...
            'Color', [0.45 0.45 0.45], 'LineWidth', 1.0, 'HandleVisibility', 'off');
    end
    artifact_color = [0.53 0.35 0.72];
    rectangle(ax,'Position',[0 artifact_y-0.15 max(n_samples/config.fs,eps) 0.30], ...
        'FaceColor','w','EdgeColor',[0.80 0.80 0.80],'HandleVisibility','off', ...
        'Tag','RespiratoryArtifactTimeline');
    for i = 1:size(ranges,1)
        rectangle(ax,'Position',[(ranges(i,1)-1)/config.fs artifact_y-0.15 ...
            (ranges(i,2)-ranges(i,1)+1)/config.fs 0.30], ...
            'FaceColor',artifact_color,'EdgeColor','none','HandleVisibility','off', ...
            'Tag','RespiratoryArtifactInterval');
    end
    if ~artifact_qc.respiratory_artifact_annotation_known
        text(ax,0,artifact_y,'Artifact metadata unavailable','FontSize',8, ...
            'Color',[0.4 0.4 0.4],'Interpreter','none');
    end
    legend_handles(end+1) = patch(ax,NaN,NaN,artifact_color,'EdgeColor','none');
    legend_labels{end+1} = 'Respiratory artifact (excluded)';
    hold(ax, 'off');

    ax.XGrid = 'on';
    ax.YGrid = 'off';
    ax.GridAlpha = 0.12;
    ax.MinorGridAlpha = 0.08;

    % Reserve margins for long row names, state labels, and the separate key.
    drawnow;
    ax.Units = 'normalized';
    left = max(0.13, ax.TightInset(1) + 0.02);
    bottom = 0.12 + 0.04 * ~isempty(legend_handles);
    ax.Position = [left bottom 0.82-left 0.90-bottom];
    cb.Units = 'normalized';
    cb.Position = [0.84 bottom 0.014 0.90-bottom];
    if ~isempty(legend_handles)
        key = legend(ax, legend_handles, legend_labels, ...
            'Orientation', 'horizontal', 'Location', 'southoutside', ...
            'Box', 'off', 'FontSize', 10, 'AutoUpdate', 'off');
        key.Units = 'normalized';
        key.Position(1) = max(0.02, min(0.98-key.Position(3), ...
            left + (ax.Position(3)-key.Position(3))/2));
        key.Position(2) = 0.02;
    end

    save_figure(config, base_name);
    fig = [];
end

function draw_sigh_event_markers(ax, events, row, color, filled, fs, allowed_samples, marker_size)
    if isempty(events), return; end
    types = canonicalize_label_names({events.type});
    sighs = events(strcmp(types, 'sigh'));
    if isempty(sighs), return; end
    % Point events use their actual peak. Historical intervals have only a
    % representative midpoint, and their old raster files remain untouched.
    peaks = (([sighs.start_idx]+[sighs.end_idx])/2-1)/fs;
    samples = round(([sighs.start_idx]+[sighs.end_idx])/2);
    valid = samples >= 1 & samples <= numel(allowed_samples);
    valid(valid) = allowed_samples(samples(valid));
    peaks = peaks(valid);
    if isempty(peaks), return; end
    face = 'none'; if filled, face = color; end
    plot(ax, peaks, repmat(row, size(peaks)), 'o', 'LineStyle', 'none', ...
        'MarkerSize', marker_size, 'MarkerEdgeColor', color, 'MarkerFaceColor', face, ...
        'LineWidth', 1.4, 'HandleVisibility', 'off', 'Tag', 'SighEventMarkers');
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
