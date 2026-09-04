function plot_amplitude_state_diagnostic(resp_features, events_lungs, events_diaph, config, opts)
% PLOT_AMPLITUDE_STATE_DIAGNOSTIC Plot amplitude state diagnostic.
%
% Syntax:
%   plot_amplitude_state_diagnostic(resp_features, events_lungs, events_diaph, config, opts)
%
% Inputs:
%   resp_features - Respiratory-feature structure.
%   events_lungs - Event structure data.
%   events_diaph - Event structure data.
%   config - Pipeline configuration structure.
%   opts - Input value `opts`.

    lungs = resp_features.resp.lungs;
    diaph = resp_features.resp.diaph;

    fig = figure('Units', 'pixels', 'Position', near_fullscreen_figure_position(), ...
        'Visible', config.make_figs_visible, 'Color', 'w');
    tl = tiledlayout(fig, 4, 1, 'TileSpacing', 'compact', 'Padding', 'compact');
    title(tl, [opts.figure_title newline ...
        'Subject: ' num2str(config.subject) ' | Measurement: ' num2str(config.measure)])

    t_grid = resp_features.resp.time_sec;
    candidate_lungs = get_option(opts, 'candidate_mask_lungs', []);
    candidate_diaph = get_option(opts, 'candidate_mask_diaph', []);
    localized_lungs = get_option(opts, 'localized_mask_lungs', []);
    localized_diaph = get_option(opts, 'localized_mask_diaph', []);
    final_lungs = events_to_grid_mask(events_lungs, t_grid);
    final_diaph = events_to_grid_mask(events_diaph, t_grid);

    ax1 = nexttile(tl);
    plot_belt_amplitude(ax1, lungs, opts, false, 'Lungs', t_grid, ...
        candidate_lungs, localized_lungs, final_lungs);
    ax2 = nexttile(tl);
    plot_belt_amplitude(ax2, lungs, opts, true, 'Lungs', t_grid, ...
        candidate_lungs, localized_lungs, final_lungs);
    ax3 = nexttile(tl);
    plot_belt_amplitude(ax3, diaph, opts, false, 'Diaphragm', t_grid, ...
        candidate_diaph, localized_diaph, final_diaph);
    ax4 = nexttile(tl);
    plot_belt_amplitude(ax4, diaph, opts, true, 'Diaphragm', t_grid, ...
        candidate_diaph, localized_diaph, final_diaph);

    ax = [ax1 ax2 ax3 ax4];
    linkaxes(ax, 'x');
    if ~isempty(resp_features.resp.time_sec)
        xlim(ax1, [0 resp_features.resp.time_sec(end)]);
    end
    align_axes_x_widths(ax);
    set(fig, 'Visible', config.make_figs_visible);
    save_figure(config, opts.output_name);
end

function plot_belt_amplitude(ax, belt, opts, normalized, belt_name, t_grid, ...
    candidate_mask, localized_mask, final_mask)
% PLOT_BELT_AMPLITUDE Plot belt amplitude.
%
% Syntax:
%   plot_belt_amplitude(ax, belt, opts, normalized, belt_name, t_grid, candidate_mask, localized_mask, final_mask)
%
% Inputs:
%   ax - Target axes handle.
%   belt - Respiratory-cycle or belt-evidence structure.
%   opts - Input value `opts`.
%   normalized - Input value `normalized`.
%   belt_name - Input value `belt_name`.
%   t_grid - Time coordinates in seconds.
%   candidate_mask - Logical state or selection mask.
%   localized_mask - Logical state or selection mask.
%   final_mask - Logical state or selection mask.

    hold(ax, 'on');
    if normalized
        values = belt.amp_ratio_session;
        ylabel_text = 'Session ratio';
        title_suffix = 'session-normalized breath excursion';
        lower = opts.lower_ratio;
        upper = get_option(opts, 'upper_ratio', NaN);
    else
        values = belt.amp;
        ylabel_text = 'Raw belt units';
        title_suffix = 'raw breath excursion';
        lower = opts.lower_ratio * belt.session_reference_value;
        upper_ratio = get_option(opts, 'upper_ratio', NaN);
        upper = upper_ratio * belt.session_reference_value;
    end

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
    shade_state_support_on_axis(ax, t_grid, candidate_mask, localized_mask, final_mask);
    if ~isempty(candidate_mask) || ~isempty(localized_mask) || ~isempty(final_mask)
        legend(ax, 'show', 'Location', 'eastoutside');
    end
    hold(ax, 'off');
    title(ax, sprintf('%s: %s', belt_name, title_suffix));
    xlabel(ax, 'Time (s)');
    ylabel(ax, ylabel_text);
    grid(ax, 'on');
end

function add_threshold_line(ax, value, label_text)
% ADD_THRESHOLD_LINE Add threshold line.
%
% Syntax:
%   add_threshold_line(ax, value, label_text)
%
% Inputs:
%   ax - Target axes handle.
%   value - Input value `value`.
%   label_text - Label identifier or label metadata.

    if isscalar(value) && isfinite(value)
        yline(ax, value, 'r--', label_text, ...
            'LabelHorizontalAlignment', 'left', 'HandleVisibility', 'off');
    end
end

function value = get_option(opts, name, default_value)
% GET_OPTION Return option.
%
% Syntax:
%   value = get_option(opts, name, default_value)
%
% Inputs:
%   opts - Input value `opts`.
%   name - Input value `name`.
%   default_value - Input value `default_value`.
%
% Outputs:
%   value - Computed numeric value.

    value = default_value;
    if isfield(opts, name) && ~isempty(opts.(name))
        value = opts.(name);
    end
end
