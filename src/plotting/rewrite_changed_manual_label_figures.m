function rewritten = rewrite_changed_manual_label_figures( ...
    data, spo2_ref, session_reference, resp_cycles, diagnostics_desat, ...
    diagnostic_signals, event_sets, edit_info, config)
% REWRITE_CHANGED_MANUAL_LABEL_FIGURES Perform the rewrite changed manual label figures operation.
%
% Syntax:
%   rewritten = rewrite_changed_manual_label_figures(data, spo2_ref, session_reference, resp_cycles, diagnostics_desat, diagnostic_signals, event_sets, edit_info, config)
%
% Inputs:
%   data - Input physiological signal data.
%   spo2_ref - SpO2-reference structure.
%   session_reference - Session-reference metadata.
%   resp_cycles - Respiratory-cycle structure.
%   diagnostics_desat - Detector diagnostic data.
%   diagnostic_signals - Detector diagnostic data.
%   event_sets - Input value `event_sets`.
%   edit_info - Input value `edit_info`.
%   config - Pipeline configuration structure.
%
% Outputs:
%   rewritten - Computed output value `rewritten`.

    rewritten = {};

    if nargin < 9 || isempty(edit_info) || ~isstruct(edit_info)
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
            data, spo2_ref, session_reference, resp_cycles, diagnostics_desat, ...
            diagnostic_signals, event_sets.(def.field), def, config);
        rewritten{end+1} = def.plot_name; %#ok<AGROW>
        fprintf('Rewrote manual-edited label figure: %s\n', def.plot_name);
    end
end

function tf = should_rewrite_any(config)
% SHOULD_REWRITE_ANY Perform the should rewrite any operation.
%
% Syntax:
%   tf = should_rewrite_any(config)
%
% Inputs:
%   config - Pipeline configuration structure.
%
% Outputs:
%   tf - Computed output value `tf`.

    tf = true;
    if isfield(config, 'LabelEdit') && isfield(config.LabelEdit, 'rewrite_changed_figures')
        tf = logical(config.LabelEdit.rewrite_changed_figures);
    end
end

function tf = should_rewrite_label(config, def)
% SHOULD_REWRITE_LABEL Perform the should rewrite label operation.
%
% Syntax:
%   tf = should_rewrite_label(config, def)
%
% Inputs:
%   config - Pipeline configuration structure.
%   def - Input value `def`.
%
% Outputs:
%   tf - Computed output value `tf`.

    tf = true;
    cfg_field = def.config_field;
    if isfield(config, cfg_field) && isfield(config.(cfg_field), 'do_plot')
        tf = logical(config.(cfg_field).do_plot);
    end
end

function plot_final_manual_label_figure( ...
    data, spo2_ref, session_reference, resp_cycles, diagnostics_desat, ...
    diagnostic_signals, events, def, config)
% PLOT_FINAL_MANUAL_LABEL_FIGURE Plot final manual label figure.
%
% Syntax:
%   plot_final_manual_label_figure(data, spo2_ref, session_reference, resp_cycles, diagnostics_desat, diagnostic_signals, events, def, config)
%
% Inputs:
%   data - Input physiological signal data.
%   spo2_ref - SpO2-reference structure.
%   session_reference - Session-reference metadata.
%   resp_cycles - Respiratory-cycle structure.
%   diagnostics_desat - Detector diagnostic data.
%   diagnostic_signals - Detector diagnostic data.
%   events - Event structure data.
%   def - Input value `def`.
%   config - Pipeline configuration structure.

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
    plot_spo2_panel(ax3, t_raw, data, spo2_ref, session_reference, ...
        diagnostics_desat, config, events);

    ax4 = nexttile(tl);
    plot_diagnostic_panel(ax4, diagnostic_signals, resp_cycles, events, def, config);

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
% PLOT_SIGNAL_PANEL Plot signal panel.
%
% Syntax:
%   plot_signal_panel(ax, t_raw, data, idx, events, title_text, y_text)
%
% Inputs:
%   ax - Target axes handle.
%   t_raw - Time coordinates in seconds.
%   data - Input physiological signal data.
%   idx - Input value `idx`.
%   events - Event structure data.
%   title_text - Input value `title_text`.
%   y_text - Input value `y_text`.

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

function plot_spo2_panel( ...
    ax, t_raw, data, spo2_ref, session_reference, diagnostics_desat, config, events)
% PLOT_SPO2_PANEL Plot spo2 panel.
%
% Syntax:
%   plot_spo2_panel(ax, t_raw, data, spo2_ref, session_reference, diagnostics_desat, config, events)
%
% Inputs:
%   ax - Target axes handle.
%   t_raw - Time coordinates in seconds.
%   data - Input physiological signal data.
%   spo2_ref - SpO2-reference structure.
%   session_reference - Session-reference metadata.
%   diagnostics_desat - Detector diagnostic data.
%   config - Pipeline configuration structure.
%   events - Event structure data.

    hold(ax, 'on');
    spo2 = [];
    if isstruct(diagnostics_desat) && isfield(diagnostics_desat, 'spo2') && ...
            numel(diagnostics_desat.spo2) == numel(t_raw)
        spo2 = diagnostics_desat.spo2(:);
    end
    idx = [];
    if isfield(config, 'channels')
        idx = config.channels.spo2_idx;
    end
    if isempty(spo2) && ~isempty(idx)
        spo2 = data(:, idx);
    end
    if isempty(spo2)
        text(ax, 0.5, 0.5, 'SpO2 channel not found', ...
            'Units', 'normalized', 'HorizontalAlignment', 'center');
    else
        plot(ax, t_raw, spo2, 'k', 'DisplayName', 'SpO2');
        shade_session_reference_on_axis( ...
            ax, session_reference, 'common session-reference interval');
        if isfield(spo2_ref, 'median_percent') && isfinite(spo2_ref.median_percent)
            yline(ax, spo2_ref.median_percent, 'k--', 'Session reference', ...
                'LabelHorizontalAlignment', 'left', 'HandleVisibility', 'off');
        end
        if isfield(config, 'desat') && isfield(config.desat, 'spo2_floor') && isfinite(config.desat.spo2_floor)
            yline(ax, config.desat.spo2_floor, 'r--', 'SpO2 floor', ...
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

function plot_diagnostic_panel(ax, diagnostic_signals, resp_cycles, events, def, config)
% PLOT_DIAGNOSTIC_PANEL Plot diagnostic panel.
%
% Syntax:
%   plot_diagnostic_panel(ax, diagnostic_signals, resp_cycles, events, def, config)
%
% Inputs:
%   ax - Target axes handle.
%   diagnostic_signals - Detector diagnostic data.
%   resp_cycles - Respiratory-cycle structure.
%   events - Event structure data.
%   def - Input value `def`.
%   config - Pipeline configuration structure.

    hold(ax, 'on');
    plotted = false;

    if isstruct(diagnostic_signals) && isfield(diagnostic_signals, 'time_sec')
        t = diagnostic_signals.time_sec(:);
        switch def.field
            case 'shallow'
                plotted = plot_metric_pair(ax, t, diagnostic_signals, ...
                    'breath_amplitude_ratio_to_reference_lungs', ...
                    'breath_amplitude_ratio_to_reference_diaph', ...
                    'Amplitude ratio to reference', 'Median breath amplitude ratio');
                if plotted && isfield(config, 'shallow')
                    yline_if_finite(ax, config.shallow.amp_ratio_low, 'r--', 'Lower threshold');
                    yline_if_finite(ax, config.shallow.amp_ratio_high, 'r--', 'Upper threshold');
                end

            case 'deep'
                plotted = plot_metric_pair(ax, t, diagnostic_signals, ...
                    'deep_breath_amplitude_ratio_to_reference_lungs', ...
                    'deep_breath_amplitude_ratio_to_reference_diaph', ...
                    'Amplitude ratio to session reference', ...
                    'Breath excursion evidence for deep breathing');
                if plotted && isfield(config, 'deep')
                    yline_if_finite(ax, config.deep.amp_ratio_thr, 'r--', 'Deep threshold');
                end

            case 'thoracic'
                plotted = plot_metric(ax, t, diagnostic_signals, ...
                    'thoracic_to_abdominal_ratio', [0.85 0.33 0.10], ...
                    'Thoracic / abdominal normalized excursion');
                if plotted && isfield(config, 'thoracic')
                    yline_if_finite(ax, config.thoracic.dominance_ratio_thr, ...
                        'r--', 'Operational dominance threshold');
                    ylabel(ax, 'Within-record ratio');
                    title(ax, 'Relative thoracoabdominal excursion balance');
                end

            case 'irregular'
                metric = irregular_metric_name(config);
                plotted = plot_metric_pair(ax, t, diagnostic_signals, metric.lungs, metric.diaph, ...
                    metric.ylabel, metric.title);
                if plotted
                    yline_if_finite(ax, metric.threshold, 'r--', 'Threshold');
                end

            case 'slow'
                plotted = plot_metric_pair(ax, t, diagnostic_signals, ...
                    'breathing_rate_slow_window_bpm_lungs', ...
                    'breathing_rate_slow_window_bpm_diaph', ...
                    'Breaths/min', '60-s window RR = 60/mean(IBI) for slow breathing');
                if plotted && isfield(config, 'slow')
                    yline_if_finite(ax, config.slow.rr_thr_bpm, 'r--', 'Slow threshold');
                end

            case 'rapid'
                plotted = plot_metric_pair(ax, t, diagnostic_signals, ...
                    'breathing_rate_rapid_window_bpm_lungs', ...
                    'breathing_rate_rapid_window_bpm_diaph', ...
                    'Breaths/min', '60-s window RR = 60/mean(IBI) for rapid breathing');
                if plotted && isfield(config, 'rapid')
                    yline_if_finite(ax, config.rapid.rr_thr_bpm, 'r--', 'Rapid threshold');
                end

            case 'async'
                plotted = plot_async_metrics(ax, t, diagnostic_signals);

            case 'desat'
                plotted = plot_metric(ax, t, diagnostic_signals, 'spo2_drop_from_reference_percent', ...
                    [0.00 0.35 0.85], 'SpO2 drop from session reference');
                if plotted && isfield(config, 'desat')
                    yline_if_finite(ax, config.desat.drop_thr, 'r--', 'Drop threshold');
                end
                ylabel(ax, 'Percent points');
                title(ax, 'SpO2 drop diagnostic');
        end
    end

    if ~plotted && strcmp(def.field, 'apnea')
        plotted = plot_resp_amplitude(ax, resp_cycles);
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
% PLOT_METRIC_PAIR Plot metric pair.
%
% Syntax:
%   plotted = plot_metric_pair(ax, t, diagnostic_signals, lungs_field, diaph_field, y_text, title_text)
%
% Inputs:
%   ax - Target axes handle.
%   t - Time coordinates in seconds.
%   diagnostic_signals - Detector diagnostic data.
%   lungs_field - Input value `lungs_field`.
%   diaph_field - Input value `diaph_field`.
%   y_text - Input value `y_text`.
%   title_text - Input value `title_text`.
%
% Outputs:
%   plotted - Computed output value `plotted`.

    plotted_lungs = plot_metric(ax, t, diagnostic_signals, lungs_field, [0.00 0.35 0.85], 'Lungs');
    plotted_diaph = plot_metric(ax, t, diagnostic_signals, diaph_field, [0.85 0.33 0.10], 'Diaphragm');
    plotted = plotted_lungs || plotted_diaph;
    if plotted
        ylabel(ax, y_text);
        title(ax, title_text);
    end
end

function plotted = plot_metric(ax, t, diagnostic_signals, field, color, display_name)
% PLOT_METRIC Plot metric.
%
% Syntax:
%   plotted = plot_metric(ax, t, diagnostic_signals, field, color, display_name)
%
% Inputs:
%   ax - Target axes handle.
%   t - Time coordinates in seconds.
%   diagnostic_signals - Detector diagnostic data.
%   field - Input value `field`.
%   color - Input value `color`.
%   display_name - Input value `display_name`.
%
% Outputs:
%   plotted - Computed output value `plotted`.

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
% IRREGULAR_METRIC_NAME Perform the irregular metric name operation.
%
% Syntax:
%   metric = irregular_metric_name(config)
%
% Inputs:
%   config - Pipeline configuration structure.
%
% Outputs:
%   metric - Computed output value `metric`.

    detection_metric = 'cov';
    if isfield(config, 'irregular') && isfield(config.irregular, 'detection_metric')
        detection_metric = char(string(config.irregular.detection_metric));
    end

    if any(strcmpi(strtrim(detection_metric), {'cov', 'plain_cov'}))
        metric.lungs = 'irregularity_cov_lungs';
        metric.diaph = 'irregularity_cov_diaph';
        metric.threshold = NaN;
        if isfield(config, 'irregular') && isfield(config.irregular, 'cov_thr')
            metric.threshold = config.irregular.cov_thr;
        end
        metric.title = 'IBI CoV for irregular breathing';
        metric.ylabel = 'CoV';
    else
        metric.lungs = 'irregularity_robust_cov_lungs';
        metric.diaph = 'irregularity_robust_cov_diaph';
        metric.threshold = NaN;
        if isfield(config, 'irregular') && isfield(config.irregular, 'robust_cov_thr')
            metric.threshold = config.irregular.robust_cov_thr;
        end
        metric.title = 'Robust IBI CoV for irregular breathing';
        metric.ylabel = 'Robust CoV';
    end
end

function plotted = plot_async_metrics(ax, t, diagnostic_signals)
% PLOT_ASYNC_METRICS Plot async metrics.
%
% Syntax:
%   plotted = plot_async_metrics(ax, t, diagnostic_signals)
%
% Inputs:
%   ax - Target axes handle.
%   t - Time coordinates in seconds.
%   diagnostic_signals - Detector diagnostic data.
%
% Outputs:
%   plotted - Computed output value `plotted`.

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

function plotted = plot_resp_amplitude(ax, resp_cycles)
% PLOT_RESP_AMPLITUDE Plot resp amplitude.
%
% Syntax:
%   plotted = plot_resp_amplitude(ax, resp_cycles)
%
% Inputs:
%   ax - Target axes handle.
%   resp_cycles - Respiratory-cycle structure.
%
% Outputs:
%   plotted - Computed output value `plotted`.

    plotted = false;
    if isfield(resp_cycles, 'lungs') && isfield(resp_cycles.lungs, 'peak_t') && isfield(resp_cycles.lungs, 'amp') && ...
            ~isempty(resp_cycles.lungs.peak_t) && ~isempty(resp_cycles.lungs.amp)
        n = min(numel(resp_cycles.lungs.peak_t), numel(resp_cycles.lungs.amp));
        scatter(ax, resp_cycles.lungs.peak_t(1:n), resp_cycles.lungs.amp(1:n), 8, ...
            [0.00 0.35 0.85], 'filled', 'DisplayName', 'Lungs amplitude');
        plotted = true;
    end
    if isfield(resp_cycles, 'diaph') && isfield(resp_cycles.diaph, 'peak_t') && isfield(resp_cycles.diaph, 'amp') && ...
            ~isempty(resp_cycles.diaph.peak_t) && ~isempty(resp_cycles.diaph.amp)
        n = min(numel(resp_cycles.diaph.peak_t), numel(resp_cycles.diaph.amp));
        scatter(ax, resp_cycles.diaph.peak_t(1:n), resp_cycles.diaph.amp(1:n), 8, ...
            [0.85 0.33 0.10], 'filled', 'DisplayName', 'Diaphragm amplitude');
        plotted = true;
    end
    if plotted
        title(ax, 'Breath amplitude diagnostics');
        ylabel(ax, 'Amplitude');
    end
end

function yline_if_finite(ax, value, style, label_text)
% YLINE_IF_FINITE Perform the yline if finite operation.
%
% Syntax:
%   yline_if_finite(ax, value, style, label_text)
%
% Inputs:
%   ax - Target axes handle.
%   value - Input value `value`.
%   style - Input value `style`.
%   label_text - Label identifier or label metadata.

    if isempty(value) || ~isscalar(value) || ~isfinite(value)
        return;
    end
    yline(ax, value, style, label_text, ...
        'LabelHorizontalAlignment', 'left', ...
        'HandleVisibility', 'off');
end
