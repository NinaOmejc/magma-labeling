function rewritten = rewrite_changed_manual_label_figures(data, baseline, resp_feat, spo2_feat, diagnostic_signals, event_sets, edit_info, config)
% rewrite_changed_manual_label_figures
% Overwrite changed diagnostics using config.fs master sample times.

    rewritten = {};

    if nargin < 8 || isempty(edit_info) || ~isstruct(edit_info)
        return;
    end
    if ~isfield(edit_info, 'changed_fields') || isempty(edit_info.changed_fields)
        return;
    end
    if ~should_rewrite_any(config)
        return;
    end

    label_defs = manual_label_definitions();
    changed_fields = edit_info.changed_fields;

    for i = 1:numel(label_defs)
        def = label_defs(i);
        if ~any(strcmp(changed_fields, def.field))
            continue;
        end
        if ~should_rewrite_label(config, def)
            continue;
        end

        plot_final_manual_label_figure( ...
            data, baseline, resp_feat, spo2_feat, diagnostic_signals, event_sets.(def.field), def, config);
        rewritten{end+1} = def.plot_name; %#ok<AGROW>
        fprintf('Rewrote manual-edited label figure: %s\n', def.plot_name);
    end
end

function tf = should_rewrite_any(config)
    tf = true;
    if isfield(config, 'LabelEdit') && isfield(config.LabelEdit, 'rewrite_changed_figures')
        tf = logical(config.LabelEdit.rewrite_changed_figures);
    end
end

function tf = should_rewrite_label(config, def)
    tf = true;
    cfg_field = def.config_field;
    if isfield(config, cfg_field) && isfield(config.(cfg_field), 'do_plot')
        tf = logical(config.(cfg_field).do_plot);
    end
end

function plot_final_manual_label_figure(data, baseline, resp_feat, spo2_feat, diagnostic_signals, events, def, config)
    if ~isfield(config, 'channels')
        config = resolve_signal_channels(config);
    end

    fs = config.fs;
    N = size(data, 1);
    t_raw = (0:N-1)' / fs;

    fig = figure('Units', 'pixels', 'Position', near_fullscreen_figure_position(), ...
        'Visible', config.make_figs_visible, 'Color', 'w');
    tl = tiledlayout(4, 1, 'TileSpacing', 'compact', 'Padding', 'compact');
    title(tl, [upper(def.name) ' | final events after manual editing' newline ...
        'Subject: ' num2str(config.subject) ' | Measurement: ' num2str(config.measure)])

    ax1 = nexttile(tl);
    plot_signal_panel(ax1, t_raw, data, config.channels.lungs_idx, events, ...
        'Resp-Lungs with final label intervals', 'Resp-Lungs');

    ax2 = nexttile(tl);
    plot_signal_panel(ax2, t_raw, data, config.channels.diaph_idx, events, ...
        'Resp-Diaphragm with final label intervals', 'Resp-Diaphragm');

    ax3 = nexttile(tl);
    plot_spo2_panel(ax3, t_raw, data, baseline, spo2_feat, config, events);

    ax4 = nexttile(tl);
    plot_diagnostic_panel(ax4, diagnostic_signals, resp_feat, events, def, config);

    ax = [ax1 ax2 ax3 ax4];
    linkaxes(ax, 'x');
    if ~isempty(t_raw)
        xlim(ax1, [0 max(t_raw(end), 1 / max(fs, 1))]);
    end
    align_axes_x_widths(ax);
    set(fig, 'Visible', config.make_figs_visible);
    save_figure(config, def.plot_name);
end

function plot_signal_panel(ax, t_raw, data, idx, events, title_text, y_text)
    hold(ax, 'on');
    if isempty(idx)
        text(ax, 0.5, 0.5, [y_text ' channel not found'], ...
            'Units', 'normalized', 'HorizontalAlignment', 'center');
    else
        plot(ax, t_raw, data(:, idx), 'k', 'DisplayName', y_text);
    end
    shade_events_on_axis(ax, events, 'Final event intervals');
    hold(ax, 'off');
    title(ax, title_text);
    xlabel(ax, 'Time (s)');
    ylabel(ax, y_text);
    grid(ax, 'on');
end

function plot_spo2_panel(ax, t_raw, data, baseline, spo2_feat, config, events)
    hold(ax, 'on');
    idx = [];
    if isfield(config, 'channels')
        idx = config.channels.spo2_idx;
    end
    if isempty(idx) && isfield(spo2_feat, 'idx_spo2')
        idx = spo2_feat.idx_spo2;
    end

    if isempty(idx)
        text(ax, 0.5, 0.5, 'SpO2 channel not found', ...
            'Units', 'normalized', 'HorizontalAlignment', 'center');
    else
        plot(ax, t_raw, data(:, idx), 'k', 'DisplayName', 'SpO2');
        if isfield(baseline, 'SpO2_median') && isfinite(baseline.SpO2_median)
            yline(ax, baseline.SpO2_median, 'k--', 'Baseline', ...
                'LabelHorizontalAlignment', 'left', 'HandleVisibility', 'off');
        end
        if isfield(config, 'spo2') && isfield(config.spo2, 'spo2_floor') && isfinite(config.spo2.spo2_floor)
            yline(ax, config.spo2.spo2_floor, 'r--', 'SpO2 floor', ...
                'LabelHorizontalAlignment', 'left', 'HandleVisibility', 'off');
        end
    end
    shade_events_on_axis(ax, events, 'Final event intervals');
    hold(ax, 'off');
    title(ax, 'SpO2 with final label intervals');
    xlabel(ax, 'Time (s)');
    ylabel(ax, 'SpO2');
    grid(ax, 'on');
end

function plot_diagnostic_panel(ax, diagnostic_signals, resp_feat, events, def, config)
    hold(ax, 'on');
    plotted = false;

    if isstruct(diagnostic_signals) && isfield(diagnostic_signals, 'time_sec')
        t = diagnostic_signals.time_sec(:);
        switch def.field
            case 'shallowB'
                plotted = plot_metric_pair(ax, t, diagnostic_signals, ...
                    'breath_amplitude_ratio_to_reference_lungs', ...
                    'breath_amplitude_ratio_to_reference_diaph', ...
                    'Amplitude ratio to reference', 'Median breath amplitude ratio');
                if plotted && isfield(config, 'ShB')
                    yline_if_finite(ax, config.ShB.amp_ratio_low, 'r--', 'Lower threshold');
                    yline_if_finite(ax, config.ShB.amp_ratio_high, 'r--', 'Upper threshold');
                end

            case 'deepB'
                plotted = plot_metric_pair(ax, t, diagnostic_signals, ...
                    'deep_breath_amplitude_ratio_to_reference_lungs', ...
                    'deep_breath_amplitude_ratio_to_reference_diaph', ...
                    'Amplitude ratio to session reference', ...
                    'Breath excursion evidence for deep breathing');
                if plotted && isfield(config, 'DeB')
                    yline_if_finite(ax, config.DeB.amp_ratio_thr, 'r--', 'Deep threshold');
                end

            case 'irregB'
                metric = irregular_metric_name(config);
                plotted = plot_metric_pair(ax, t, diagnostic_signals, metric.lungs, metric.diaph, ...
                    metric.ylabel, metric.title);
                if plotted
                    yline_if_finite(ax, metric.threshold, 'r--', 'Threshold');
                end

            case 'slowB'
                plotted = plot_metric_pair(ax, t, diagnostic_signals, ...
                    'breathing_rate_slow_window_bpm_lungs', ...
                    'breathing_rate_slow_window_bpm_diaph', ...
                    'Breaths/min', 'Mean respiratory rate for slow breathing');
                if plotted && isfield(config, 'SlB')
                    yline_if_finite(ax, config.SlB.rr_thr_bpm, 'r--', 'Slow threshold');
                end

            case 'rapidB'
                plotted = plot_metric_pair(ax, t, diagnostic_signals, ...
                    'breathing_rate_rapid_window_bpm_lungs', ...
                    'breathing_rate_rapid_window_bpm_diaph', ...
                    'Breaths/min', 'Mean respiratory rate for rapid breathing');
                if plotted && isfield(config, 'RaB')
                    yline_if_finite(ax, config.RaB.rr_thr_bpm, 'r--', 'Rapid threshold');
                end

            case 'asyncB'
                plotted = plot_async_metrics(ax, t, diagnostic_signals);

            case 'desat'
                plotted = plot_metric(ax, t, diagnostic_signals, 'spo2_drop_from_baseline_percent', ...
                    [0.00 0.35 0.85], 'SpO2 drop from baseline');
                if plotted && isfield(config, 'spo2')
                    yline_if_finite(ax, config.spo2.drop_thr, 'r--', 'Drop threshold');
                end
                ylabel(ax, 'Percent points');
                title(ax, 'SpO2 drop diagnostic');
        end
    end

    if ~plotted && strcmp(def.field, 'apnea')
        plotted = plot_resp_amplitude(ax, resp_feat);
    end

    if ~plotted
        ylim(ax, [0 1]);
        text(ax, 0.5, 0.5, 'No extra diagnostic trace saved for this label', ...
            'Units', 'normalized', 'HorizontalAlignment', 'center');
        title(ax, 'Manual event review');
        ylabel(ax, 'Diagnostic');
    end

    shade_events_on_axis(ax, events, 'Final event intervals');
    hold(ax, 'off');
    xlabel(ax, 'Time (s)');
    grid(ax, 'on');
    if plotted
        legend(ax, 'show', 'Location', 'eastoutside', 'Box', 'off');
    end
end

function plotted = plot_metric_pair(ax, t, diagnostic_signals, lungs_field, diaph_field, y_text, title_text)
    plotted_lungs = plot_metric(ax, t, diagnostic_signals, lungs_field, [0.00 0.35 0.85], 'Lungs');
    plotted_diaph = plot_metric(ax, t, diagnostic_signals, diaph_field, [0.85 0.33 0.10], 'Diaphragm');
    plotted = plotted_lungs || plotted_diaph;
    if plotted
        ylabel(ax, y_text);
        title(ax, title_text);
    end
end

function plotted = plot_metric(ax, t, diagnostic_signals, field, color, display_name)
    plotted = false;
    if ~isfield(diagnostic_signals, field)
        return;
    end
    y = diagnostic_signals.(field);
    if isempty(y)
        return;
    end
    y = y(:);
    n = min(numel(t), numel(y));
    if n == 0 || ~any(isfinite(y(1:n)))
        return;
    end
    plot(ax, t(1:n), y(1:n), 'Color', color, 'LineWidth', 1.2, 'DisplayName', display_name);
    plotted = true;
end

function metric = irregular_metric_name(config)
    detection_metric = 'cov';
    if isfield(config, 'IrB') && isfield(config.IrB, 'detection_metric')
        detection_metric = char(string(config.IrB.detection_metric));
    end

    if any(strcmpi(strtrim(detection_metric), {'cov', 'plain_cov'}))
        metric.lungs = 'irregularity_cov_lungs';
        metric.diaph = 'irregularity_cov_diaph';
        metric.threshold = NaN;
        if isfield(config, 'IrB') && isfield(config.IrB, 'cov_thr')
            metric.threshold = config.IrB.cov_thr;
        end
        metric.title = 'IBI CoV for irregular breathing';
        metric.ylabel = 'CoV';
    else
        metric.lungs = 'irregularity_robust_cov_lungs';
        metric.diaph = 'irregularity_robust_cov_diaph';
        metric.threshold = NaN;
        if isfield(config, 'IrB') && isfield(config.IrB, 'robust_cov_thr')
            metric.threshold = config.IrB.robust_cov_thr;
        end
        metric.title = 'Robust IBI CoV for irregular breathing';
        metric.ylabel = 'Robust CoV';
    end
end

function plotted = plot_async_metrics(ax, t, diagnostic_signals)
    plotted = false;
    plotted = plot_metric(ax, t, diagnostic_signals, 'resp_asynchrony_phase_coherence_high', ...
        [0.00 0.35 0.85], 'High coherence') || plotted;
    plotted = plot_metric(ax, t, diagnostic_signals, 'resp_asynchrony_phase_coherence_mid', ...
        [0.85 0.33 0.10], 'Resp-band coherence') || plotted;
    plotted = plot_metric(ax, t, diagnostic_signals, 'resp_asynchrony_phase_coherence_low', ...
        [0.25 0.55 0.25], 'Low coherence') || plotted;
    if plotted
        ylim(ax, [0 1]);
        ylabel(ax, 'WPhCoh');
        title(ax, 'Phase coherence diagnostics');
    end
end

function plotted = plot_resp_amplitude(ax, resp_feat)
    plotted = false;
    if isfield(resp_feat, 'lungs') && isfield(resp_feat.lungs, 'peak_t') && isfield(resp_feat.lungs, 'amp') && ...
            ~isempty(resp_feat.lungs.peak_t) && ~isempty(resp_feat.lungs.amp)
        n = min(numel(resp_feat.lungs.peak_t), numel(resp_feat.lungs.amp));
        scatter(ax, resp_feat.lungs.peak_t(1:n), resp_feat.lungs.amp(1:n), 8, ...
            [0.00 0.35 0.85], 'filled', 'DisplayName', 'Lungs amplitude');
        plotted = true;
    end
    if isfield(resp_feat, 'diaph') && isfield(resp_feat.diaph, 'peak_t') && isfield(resp_feat.diaph, 'amp') && ...
            ~isempty(resp_feat.diaph.peak_t) && ~isempty(resp_feat.diaph.amp)
        n = min(numel(resp_feat.diaph.peak_t), numel(resp_feat.diaph.amp));
        scatter(ax, resp_feat.diaph.peak_t(1:n), resp_feat.diaph.amp(1:n), 8, ...
            [0.85 0.33 0.10], 'filled', 'DisplayName', 'Diaphragm amplitude');
        plotted = true;
    end
    if plotted
        title(ax, 'Breath amplitude diagnostics');
        ylabel(ax, 'Amplitude');
    end
end

function yline_if_finite(ax, value, style, label_text)
    if isempty(value) || ~isscalar(value) || ~isfinite(value)
        return;
    end
    yline(ax, value, style, label_text, ...
        'LabelHorizontalAlignment', 'left', ...
        'HandleVisibility', 'off');
end
