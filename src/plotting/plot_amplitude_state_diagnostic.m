function plot_amplitude_state_diagnostic(resp_features, events_lungs, events_diaph, config, opts)
% PLOT_AMPLITUDE_STATE_DIAGNOSTIC Plot session-normalized breath excursion by belt.
%
% Inputs:
%   resp_features - Respiratory evidence; uses top-level time_sec and each belt's
%                   breath-level amp_ratio_session and reference status.
%   events_lungs  - Final lung-belt events with boundaries in seconds.
%   events_diaph  - Final diaphragm-belt events with boundaries in seconds.
%   config        - Pipeline settings for recording identity and figure output.
%   opts          - Plot text, output name, ratio thresholds, and optional
%                   localized masks on the analysis grid.

    lungs = resp_features.lungs;
    diaph = resp_features.diaph;

    fig = figure('Units', 'pixels', 'Position', near_fullscreen_figure_position(), ...
        'Visible', config.make_figs_visible, 'Color', 'w');
    tl = tiledlayout(fig, 2, 1, 'TileSpacing', 'compact', 'Padding', 'compact');
    title(tl, [opts.figure_title newline ...
        'Subject: ' num2str(config.subject) ' | Measurement: ' num2str(config.measure)])

    t_grid = resp_features.time_sec;
    localized_lungs = get_option(opts, 'localized_mask_lungs', []);
    localized_diaph = get_option(opts, 'localized_mask_diaph', []);
    final_lungs = events_to_grid_mask(events_lungs, t_grid);
    final_diaph = events_to_grid_mask(events_diaph, t_grid);

    ax1 = nexttile(tl);
    plot_belt_amplitude(ax1, lungs, opts, 'Lungs', t_grid, ...
        localized_lungs, final_lungs);
    ax2 = nexttile(tl);
    plot_belt_amplitude(ax2, diaph, opts, 'Diaphragm', t_grid, ...
        localized_diaph, final_diaph);

    ax = [ax1 ax2];
    linkaxes(ax, 'x');
    if ~isempty(resp_features.time_sec)
        xlim(ax1, [0 resp_features.time_sec(end)]);
    end
    align_axes_x_widths(ax);
    set(fig, 'Visible', config.make_figs_visible);
    save_figure(config, opts.output_name);
end

function plot_belt_amplitude(ax, belt, opts, belt_name, t_grid, ...
    localized_mask, final_mask)
% PLOT_BELT_AMPLITUDE Plot normalized breath excursion and support layers.
% Localized and final masks align with t_grid; belt_name identifies the belt.

    hold(ax, 'on');
    values = belt.amp_ratio_session;
    lower = opts.lower_ratio;
    upper = get_option(opts, 'upper_ratio', NaN);

    n = min(numel(belt.peak_t), numel(values));
    if belt.session_amplitude_available && n > 0 && any(isfinite(values(1:n)))
        scatter(ax, belt.peak_t(1:n), values(1:n), 10, 'k', 'filled', ...
            'DisplayName', 'Respiratory cycles');
        add_threshold_line(ax, lower, 'Lower threshold');
        add_threshold_line(ax, upper, 'Upper threshold');
    else
        text(ax, 0.5, 0.5, 'No usable session-normalized belt amplitude evidence', ...
            'Units', 'normalized', 'HorizontalAlignment', 'center');
    end
    shade_state_support_on_axis( ...
        ax, t_grid, [], localized_mask, final_mask, false);
    if ~isempty(localized_mask) || ~isempty(final_mask)
        legend(ax, 'show', 'Location', 'eastoutside');
    end
    hold(ax, 'off');
    title(ax, sprintf('%s: session-normalized breath excursion ratio', belt_name));
    xlabel(ax, 'Time (s)');
    ylabel(ax, 'Session ratio');
    grid(ax, 'on');
end

function add_threshold_line(ax, value, label_text)
% ADD_THRESHOLD_LINE Draw a finite scalar amplitude threshold on an axes.

    if isscalar(value) && isfinite(value)
        yline(ax, value, 'r--', label_text, ...
            'LabelHorizontalAlignment', 'left', 'HandleVisibility', 'off');
    end
end

function value = get_option(opts, name, default_value)
% GET_OPTION Return a nonempty struct option or its default value.

    value = default_value;
    if isfield(opts, name) && ~isempty(opts.(name))
        value = opts.(name);
    end
end
