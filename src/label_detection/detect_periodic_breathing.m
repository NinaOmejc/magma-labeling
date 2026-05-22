function events = detect_periodic_breathing(data, resp_feat, config)
% detect_periodic_breathing
% Label 9 - Cheyne-Stokes-like / periodic breathing.
%
% This is a simplified RIP-belt pattern detector, not a diagnostic CSR
% scorer. It detects repeated modulation of the breath-amplitude envelope:
% smaller breaths -> larger breaths -> smaller breaths, typically over
% cycles of about 40-120 s. It uses breath amplitudes, not the slow
% baseline drift of the raw belt signal.

    events = empty_events();

    N = size(data, 1);
    fs = config.new_fs;
    cfg = periodic_breathing_config(config);

    lungs_broken = is_lung_belt_ignored(config);
    lungs_valid = is_valid_breath_signal(resp_feat.lungs, true) && ~lungs_broken;
    diaph_valid = is_valid_breath_signal(resp_feat.diaph, true);

    if ~lungs_valid && ~diaph_valid
        fprintf('Skipping CSR detection: no valid respiratory belt with usable breath amplitudes.\n');
        return;
    end

    events_lungs = empty_events();
    diag_lungs = init_periodic_diag();
    if lungs_valid
        [events_lungs, diag_lungs] = periodic_breathing_events_for_belt( ...
            resp_feat.lungs, N, fs, cfg, 'lungs');
    end

    events_diaph = empty_events();
    diag_diaph = init_periodic_diag();
    if diaph_valid
        [events_diaph, diag_diaph] = periodic_breathing_events_for_belt( ...
            resp_feat.diaph, N, fs, cfg, 'diaph');
    end

    events = merge_events({events_lungs, events_diaph}, cfg.max_cycle_gap_sec);

    if cfg.do_plot
        plot_periodic_breathing_diagnostics( ...
            data, config, events, events_lungs, events_diaph, diag_lungs, diag_diaph, cfg);
    end
end

function cfg = periodic_breathing_config(config)
    cfg = struct();
    cfg.min_cycle_sec = get_config_value(config, 'CSR', 'min_cycle_sec', 35);
    cfg.max_cycle_sec = get_config_value(config, 'CSR', 'max_cycle_sec', 120);
    cfg.min_cycles = get_config_value(config, 'CSR', 'min_cycles', 2);
    cfg.min_modulation_ratio = get_config_value(config, 'CSR', 'min_modulation_ratio', 1.5);
    cfg.min_breaths_per_cycle = get_config_value(config, 'CSR', 'min_breaths_per_cycle', 3);
    cfg.min_side_breaths = get_config_value(config, 'CSR', 'min_side_breaths', 1);
    cfg.env_smooth_breaths = odd_window(get_config_value(config, 'CSR', 'env_smooth_breaths', 3));
    cfg.normalization_window_breaths = get_config_value(config, 'CSR', 'normalization_window_breaths', 0);
    if cfg.normalization_window_breaths >= 3
        cfg.normalization_window_breaths = odd_window(cfg.normalization_window_breaths);
    end
    cfg.min_peak_prominence = get_config_value(config, 'CSR', 'min_peak_prominence', 0.25);
    cfg.min_trough_prominence = get_config_value(config, 'CSR', 'min_trough_prominence', 0.15);
    cfg.min_shape_fraction = get_config_value(config, 'CSR', 'min_shape_fraction', 0.55);
    cfg.max_cycle_gap_sec = get_config_value(config, 'CSR', 'max_cycle_gap_sec', 10);
    cfg.do_plot = get_config_value(config, 'CSR', 'do_plot', false);
end

function win = odd_window(value)
    win = max(1, round(value));
    if mod(win, 2) == 0
        win = win + 1;
    end
end

function [events, diag] = periodic_breathing_events_for_belt(breaths, N, fs, cfg, belt)
    events = empty_events();
    diag = init_periodic_diag();

    [breath_t, amp] = breath_amp_vectors(breaths);
    diag.breath_t = breath_t;
    diag.amp = amp;

    if numel(breath_t) < max(6, cfg.min_breaths_per_cycle * cfg.min_cycles)
        return;
    end

    [amp_env, amp_norm] = normalized_amplitude_envelope(amp, cfg);
    diag.amp_norm = amp_norm;
    diag.amp_env = amp_env;

    cycles = find_periodic_cycles(breath_t, amp_env, cfg);
    diag.cycles = cycles;
    events = cycles_to_periodic_events(cycles, N, fs, cfg, belt);
end

function [breath_t, amp] = breath_amp_vectors(breaths)
    breath_t = [];
    amp = [];

    if isempty(breaths) || ~isstruct(breaths) || ...
            ~isfield(breaths, 'peak_t') || ~isfield(breaths, 'amp')
        return;
    end

    if isfield(breaths, 'peak_val') && isfield(breaths, 'trough_val') && ...
            numel(breaths.peak_t) >= 2 && numel(breaths.trough_val) >= 1
        peak_t = breaths.peak_t(:);
        peak_val = breaths.peak_val(:);
        trough_val = breaths.trough_val(:);
        n = min([numel(peak_t) - 1, numel(peak_val) - 1, numel(trough_val)]);

        % Breath amplitude at peak i is peak(i) minus the preceding trough.
        breath_t = peak_t(2:n+1);
        amp = peak_val(2:n+1) - trough_val(1:n);
    else
        breath_t = breaths.peak_t(:);
        amp = breaths.amp(:);
        n = min(numel(breath_t), numel(amp));
        breath_t = breath_t(1:n);
        amp = amp(1:n);
    end

    valid = isfinite(breath_t) & isfinite(amp) & amp > 0;
    breath_t = breath_t(valid);
    amp = amp(valid);

    [breath_t, order] = sort(breath_t);
    amp = amp(order);
end

function [amp_env, amp_norm] = normalized_amplitude_envelope(amp, cfg)
    amp = amp(:);

    global_ref = median(amp(isfinite(amp) & amp > 0), 'omitnan');
    if ~isfinite(global_ref) || global_ref <= 0
        global_ref = 1;
    end

    if cfg.normalization_window_breaths >= 3
        local_ref = movmedian(amp, cfg.normalization_window_breaths, 'omitnan');
        bad_ref = ~isfinite(local_ref) | local_ref <= 0;
        local_ref(bad_ref) = global_ref;
        amp_norm = amp ./ max(local_ref, eps);
    else
        amp_norm = amp ./ max(global_ref, eps);
    end

    amp_env = movmedian(amp_norm, cfg.env_smooth_breaths, 'omitnan');
end

function cycles = find_periodic_cycles(breath_t, amp_env, cfg)
    cycles = empty_cycles();

    if numel(breath_t) < 4 || all(~isfinite(amp_env))
        return;
    end

    min_extrema_distance = max(cfg.min_cycle_sec / 3, median(diff(breath_t), 'omitnan'));

    try
        [pks, pk_locs] = findpeaks(amp_env, breath_t, ...
            'MinPeakProminence', cfg.min_peak_prominence, ...
            'MinPeakDistance', min_extrema_distance);
        [troughs_neg, tr_locs] = findpeaks(-amp_env, breath_t, ...
            'MinPeakProminence', cfg.min_trough_prominence, ...
            'MinPeakDistance', min_extrema_distance);
    catch
        return;
    end

    troughs = -troughs_neg;
    pks = pks(:);
    pk_locs = pk_locs(:);
    troughs = troughs(:);
    tr_locs = tr_locs(:);

    if numel(tr_locs) < 2
        return;
    end

    for i = 1:numel(tr_locs)-1
        t1 = tr_locs(i);
        t2 = tr_locs(i+1);
        cycle_dur = t2 - t1;

        if cycle_dur < cfg.min_cycle_sec || cycle_dur > cfg.max_cycle_sec
            continue;
        end

        in_cycle = breath_t >= t1 & breath_t <= t2;
        cycle_idx = find(in_cycle);
        n_breaths = numel(cycle_idx);
        if n_breaths < cfg.min_breaths_per_cycle
            continue;
        end

        [peak_amp, peak_t] = cycle_peak_between_troughs( ...
            breath_t, amp_env, pks, pk_locs, t1, t2, cycle_idx);
        if ~isfinite(peak_amp) || ~isfinite(peak_t)
            continue;
        end

        n_rise = sum(breath_t >= t1 & breath_t <= peak_t);
        n_fall = sum(breath_t >= peak_t & breath_t <= t2);
        if n_rise < (cfg.min_side_breaths + 1) || n_fall < (cfg.min_side_breaths + 1)
            continue;
        end

        trough_amp = median([troughs(i), troughs(i+1)], 'omitnan');
        if ~isfinite(trough_amp) || trough_amp <= 0
            continue;
        end

        modulation_ratio = peak_amp / max(trough_amp, eps);
        if modulation_ratio < cfg.min_modulation_ratio
            continue;
        end

        shape_score = rise_fall_shape_score(breath_t, amp_env, t1, peak_t, t2);
        if shape_score < cfg.min_shape_fraction
            continue;
        end

        cycles(end+1,1) = struct( ... %#ok<AGROW>
            'start_t', t1, ...
            'end_t', t2, ...
            'duration', cycle_dur, ...
            'peak_t', peak_t, ...
            'peak_amp', peak_amp, ...
            'trough_amp', trough_amp, ...
            'modulation_ratio', modulation_ratio, ...
            'n_breaths', n_breaths, ...
            'shape_score', shape_score );
    end
end

function [peak_amp, peak_t] = cycle_peak_between_troughs( ...
    breath_t, amp_env, pks, pk_locs, t1, t2, cycle_idx)

    peak_amp = NaN;
    peak_t = NaN;

    mid_peak_idx = find(pk_locs > t1 & pk_locs < t2);
    if ~isempty(mid_peak_idx)
        [peak_amp, rel] = max(pks(mid_peak_idx), [], 'omitnan');
        peak_t = pk_locs(mid_peak_idx(rel));
        return;
    end

    env_cycle = amp_env(cycle_idx);
    breath_t_cycle = breath_t(cycle_idx);
    if numel(env_cycle) < 3
        return;
    end

    [peak_amp, rel] = max(env_cycle, [], 'omitnan');
    if rel <= 1 || rel >= numel(env_cycle)
        peak_amp = NaN;
        peak_t = NaN;
        return;
    end
    peak_t = breath_t_cycle(rel);
end

function score = rise_fall_shape_score(breath_t, amp_env, t1, peak_t, t2)
    rise = amp_env(breath_t >= t1 & breath_t <= peak_t);
    fall = amp_env(breath_t >= peak_t & breath_t <= t2);

    rise_score = monotonic_fraction(rise, 1);
    fall_score = monotonic_fraction(fall, -1);
    score = min(rise_score, fall_score);
end

function frac = monotonic_fraction(values, direction)
    values = values(:);
    values = values(isfinite(values));

    if numel(values) < 2
        frac = 0;
        return;
    end

    d = diff(values);
    tol = 0.03;
    if direction > 0
        frac = mean(d >= -tol);
    else
        frac = mean(d <= tol);
    end
end

function events = cycles_to_periodic_events(cycles, N, fs, cfg, belt)
    events = empty_events();
    if isempty(cycles)
        return;
    end

    group_start = 1;
    for i = 2:numel(cycles)+1
        close_to_previous = false;
        if i <= numel(cycles)
            close_to_previous = cycles(i).start_t <= cycles(i-1).end_t + cfg.max_cycle_gap_sec;
        end

        if close_to_previous
            continue;
        end

        group_end = i - 1;
        if (group_end - group_start + 1) >= cfg.min_cycles
            start_t = cycles(group_start).start_t;
            end_t = cycles(group_end).end_t;
            events(end+1,1) = make_periodic_event(start_t, end_t, N, fs, belt); %#ok<AGROW>
        end
        group_start = i;
    end
end

function event = make_periodic_event(start_t, end_t, N, fs, belt)
    start_idx = max(1, min(N, round(start_t * fs) + 1));
    end_idx = max(1, min(N, round(end_t * fs) + 1));

    event = struct( ...
        'type', ['periodic_breathing_' belt], ...
        'start_idx', start_idx, ...
        'end_idx', end_idx, ...
        'start_t', (start_idx - 1) / fs, ...
        'end_t', (end_idx - 1) / fs, ...
        'duration', (end_idx - start_idx) / fs );
end

function cycles = empty_cycles()
    cycles = struct( ...
        'start_t', {}, ...
        'end_t', {}, ...
        'duration', {}, ...
        'peak_t', {}, ...
        'peak_amp', {}, ...
        'trough_amp', {}, ...
        'modulation_ratio', {}, ...
        'n_breaths', {}, ...
        'shape_score', {} );
end

function diag = init_periodic_diag()
    diag = struct( ...
        'breath_t', [], ...
        'amp', [], ...
        'amp_norm', [], ...
        'amp_env', [], ...
        'cycles', empty_cycles() );
end

function plot_periodic_breathing_diagnostics( ...
    data, config, events, events_lungs, events_diaph, diag_lungs, diag_diaph, cfg)

    N = size(data, 1);
    t_raw = (0:N-1) / config.new_fs;
    if ~isfield(config, 'channels')
        config = resolve_signal_channels(config);
    end
    idx_lungs = config.channels.lungs_idx;
    idx_diaph = config.channels.diaph_idx;

    fig = figure('Units', 'pixels', 'Position', near_fullscreen_figure_position(), ...
        'Visible', config.make_figs_visible);
    sgtitle(['PERIODIC BREATHING / CHEYNE-STOKES-LIKE' newline ...
        'Subject: ' num2str(config.subject) ' | Measurement: ' num2str(config.measure)])

    ax1 = subplot(3, 1, 1); hold on
    plot_resp_trace_or_message(t_raw, data, idx_lungs, 'Resp-Lungs');
    shade_events_on_axis(gca, events_lungs, 'periodic breathing lungs');
    title('Lungs raw signal')
    xlabel('Time (s)'); ylabel('Resp-Lungs'); grid on
    hold off

    ax2 = subplot(3, 1, 2); hold on
    plot_resp_trace_or_message(t_raw, data, idx_diaph, 'Resp-Diaphragm');
    shade_events_on_axis(gca, events_diaph, 'periodic breathing diaphragm');
    title('Diaphragm raw signal')
    xlabel('Time (s)'); ylabel('Resp-Diaphragm'); grid on
    hold off

    ax3 = subplot(3, 1, 3); hold on
    plot_envelope_trace(diag_lungs, [0.1 0.1 0.1], 'lungs envelope');
    plot_envelope_trace(diag_diaph, [0.1 0.35 0.9], 'diaph envelope');
    yline(1.0, 'k:');
    shade_events_on_axis(gca, events, 'periodic breathing');
    title(sprintf('Normalized breath-amplitude envelope | cycles %d-%d s | ratio >= %.2f', ...
        cfg.min_cycle_sec, cfg.max_cycle_sec, cfg.min_modulation_ratio))
    xlabel('Time (s)'); ylabel('Normalized envelope'); grid on
    legend('Location', 'eastoutside')
    hold off

    ax = [ax1 ax2 ax3];
    linkaxes(ax, 'x');
    xlim(ax1, [0 t_raw(end)]);
    align_axes_x_widths(ax);

    set(fig, 'Visible', config.make_figs_visible);
    save_figure(config, 'periodic_breathing');
end

function plot_envelope_trace(diag, color, display_name)
    if isempty(diag.breath_t) || isempty(diag.amp_env)
        return;
    end

    plot(diag.breath_t, diag.amp_env, '-', 'Color', color, ...
        'LineWidth', 1.3, 'DisplayName', display_name);
    scatter(diag.breath_t, diag.amp_env, 10, color, 'filled', ...
        'DisplayName', [display_name ' breaths']);

    for i = 1:numel(diag.cycles)
        c = diag.cycles(i);
        plot([c.start_t c.peak_t c.end_t], ...
            [c.trough_amp c.peak_amp c.trough_amp], 'o-', ...
            'Color', color, 'MarkerFaceColor', color, ...
            'HandleVisibility', 'off');
    end
end

function plot_resp_trace_or_message(t_raw, data, idx, label_text)
    if isempty(idx)
        text(0.5, 0.5, [label_text ' channel not found'], ...
            'Units', 'normalized', 'HorizontalAlignment', 'center')
    else
        plot(t_raw, data(:, idx), 'k')
    end
end
