function plot_amplitude_state_diagnostic( ...
    data, resp_features, events_lungs, events_diaph, config, opts)
% PLOT_AMPLITUDE_STATE_DIAGNOSTIC Pair raw belts with amplitude evidence.
%
% Inputs:
%   data          - Nsample x Nchannel raw physiological signals.
%   resp_features - Respiratory evidence; uses top-level time_sec and each belt's
%                   breath-level amp_ratio_session and reference status.
%   events_lungs  - Final lung-belt events with boundaries in seconds.
%   events_diaph  - Final diaphragm-belt events with boundaries in seconds.
%   config        - Pipeline settings for recording identity and figure output.
%   opts          - Plot text, output name, ratio thresholds, and optional
%                   localized masks on the analysis grid.

    lungs = resp_features.lungs;
    diaph = resp_features.diaph;
    if ~isfield(config, 'channels')
        config = resolve_signal_channels(config);
    end
    idx_lungs = config.channels.lungs_idx;
    idx_diaph = config.channels.diaph_idx;
    t_raw = (0:size(data, 1) - 1) / config.fs;

    fig = figure('Units', 'pixels', 'Position', near_fullscreen_figure_position(), ...
        'Visible', config.make_figs_visible, 'Color', 'w');
    tl = tiledlayout(fig, 4, 1, 'TileSpacing', 'compact', 'Padding', 'compact');
    title(tl, [opts.figure_title newline ...
        'Subject: ' num2str(config.subject) ' | Measurement: ' num2str(config.measure)])

    t_grid = resp_features.time_sec;
    localized_lungs = get_option(opts, 'localized_mask_lungs', []);
    localized_diaph = get_option(opts, 'localized_mask_diaph', []);
    final_lungs = events_to_grid_mask(events_lungs, t_grid);
    final_diaph = events_to_grid_mask(events_diaph, t_grid);
    final_events = merge_events({events_lungs, events_diaph});

    ax1 = nexttile(tl);
    plot_raw_belt(ax1, t_raw, data, idx_lungs, 'Resp-Lungs', ...
        opts.event_name, final_events);
    ax2 = nexttile(tl);
    plot_belt_amplitude(ax2, lungs, opts, 'Lungs', t_grid, ...
        localized_lungs, final_lungs);
    ax3 = nexttile(tl);
    plot_raw_belt(ax3, t_raw, data, idx_diaph, 'Resp-Diaphragm', ...
        opts.event_name, final_events);
    ax4 = nexttile(tl);
    plot_belt_amplitude(ax4, diaph, opts, 'Diaphragm', t_grid, ...
        localized_diaph, final_diaph);

    ax = [ax1 ax2 ax3 ax4];
    linkaxes(ax, 'x');
    if ~isempty(t_raw)
        xlim(ax1, [0 t_raw(end)]);
    end
    align_axes_x_widths(ax);
    set(fig, 'Visible', config.make_figs_visible);
    save_figure(config, opts.output_name);
end

function plot_raw_belt(ax, t_raw, data, channel_index, signal_name, ...
    event_name, final_events)
% PLOT_RAW_BELT Show one raw belt with the merged final label events.

    hold(ax, 'on');
    has_trace = isscalar(channel_index) && isfinite(channel_index) && ...
        channel_index >= 1 && channel_index <= size(data, 2);
    if has_trace
        plot(ax, t_raw, data(:, channel_index), 'k', ...
            'DisplayName', signal_name);
    else
        text(ax, 0.5, 0.5, [signal_name ' channel not found'], ...
            'Units', 'normalized', 'HorizontalAlignment', 'center');
    end
    shade_events_on_axis(ax, final_events, ['final ' lower(event_name) ' label']);
    if has_trace || ~isempty(final_events)
        legend(ax, 'show', 'Location', 'eastoutside', 'Box', 'off');
    end
    hold(ax, 'off');
    title(ax, sprintf('%s final label over raw %s signal', ...
        event_name, lower(strrep(signal_name, 'Resp-', ''))));
    xlabel(ax, 'Time (s)');
    ylabel(ax, signal_name);
    grid(ax, 'on');
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
