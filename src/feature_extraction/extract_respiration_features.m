function resp_cycles = extract_respiration_features(data, config)
% EXTRACT_RESPIRATION_FEATURES Extract respiration features.
%
% Syntax:
%   resp_cycles = extract_respiration_features(data, config)
%
% Inputs:
%   data - Input physiological signal data.
%   config - Pipeline configuration structure.
%
% Outputs:
%   resp_cycles - Respiratory-cycle structure.

    if ~isfield(config, 'channels')
        config = resolve_signal_channels(config);
    end
    idx_lungs = config.channels.lungs_idx;
    idx_diaph = config.channels.diaph_idx;

    % ---- breath series (peaks + per-breath amplitudes) ----
    resp_cycles = struct();
    if ~isempty(idx_lungs)
        resp_cycles.lungs = extract_respiration_feature(data(:, idx_lungs), config, 'lungs');
    else
        resp_cycles.lungs = empty_respiration_feature('lungs');
    end
    if ~isempty(idx_diaph)
        resp_cycles.diaph = extract_respiration_feature(data(:, idx_diaph), config, 'diaph');
    else
        resp_cycles.diaph = empty_respiration_feature('diaph');
    end

    review_status = 'automatic';
    manual_review_performed = false;
    manual_edits_made = false;

    if isfield(config.resp, 'manual_control') && config.resp.manual_control
        edit_lungs = is_editable_resp_signal(resp_cycles.lungs) && ~is_lung_belt_ignored(config);
        edit_diaph = is_editable_resp_signal(resp_cycles.diaph);

        if edit_lungs || edit_diaph
            peak_idx_lungs_before = resp_cycles.lungs.peak_idx;
            peak_idx_diaph_before = resp_cycles.diaph.peak_idx;
            [edited_lungs, edited_diaph, review_confirmed] = ...
                manual_edit_respiration_features( ...
                data, resp_cycles.lungs, resp_cycles.diaph, config);
            if review_confirmed
                resp_cycles.lungs = edited_lungs;
                resp_cycles.diaph = edited_diaph;
                manual_review_performed = true;
                manual_edits_made = ...
                    (edit_lungs && peak_indices_changed( ...
                        peak_idx_lungs_before, resp_cycles.lungs.peak_idx)) || ...
                    (edit_diaph && peak_indices_changed( ...
                        peak_idx_diaph_before, resp_cycles.diaph.peak_idx));
                if manual_edits_made
                    review_status = 'manual_reviewed_edited';
                else
                    review_status = 'manual_reviewed_unchanged';
                end
                if isfield(config.resp, 'do_plot') && config.resp.do_plot
                    if edit_lungs
                        save_final_respiration_feature_figure( ...
                            resp_cycles.lungs, config, 'lungs');
                    end
                    if edit_diaph
                        save_final_respiration_feature_figure( ...
                            resp_cycles.diaph, config, 'diaph');
                    end
                end
            end
        else
            warning('MAGMA:Respiration:ManualSkipped', ...
                'Manual breath editing requires at least one usable respiratory belt signal and was skipped.');
        end
    end

    resp_cycles.provenance = struct( ...
        'review_status', review_status, ...
        'manual_review_performed', manual_review_performed, ...
        'manual_edits_made', manual_edits_made, ...
        'loaded_from_cache', false);
end

function tf = peak_indices_changed(before, after)
% PEAK_INDICES_CHANGED Perform the peak indices changed operation.
%
% Syntax:
%   tf = peak_indices_changed(before, after)
%
% Inputs:
%   before - Input value `before`.
%   after - Input value `after`.
%
% Outputs:
%   tf - Computed output value `tf`.

    tf = ~isequal(before(:), after(:));
end

function save_final_respiration_feature_figure(b, config, basename)
% SAVE_FINAL_RESPIRATION_FEATURE_FIGURE Save final respiration feature figure.
%
% Syntax:
%   save_final_respiration_feature_figure(b, config, basename)
%
% Inputs:
%   b - Respiratory-cycle or belt-evidence structure.
%   config - Pipeline configuration structure.
%   basename - Input value `basename`.

    if ~isfield(b, 'x0') || isempty(b.x0)
        return;
    end

    x = b.x0(:);
    t = (0:numel(x)-1) / config.fs;

    figure('Units','pixels','Position', near_fullscreen_figure_position(), 'Visible', config.make_figs_visible);
    hold on
    h_signal = plot(t, x, 'DisplayName', 'x0');
    h_peak = plot_breath_markers(b, 'peak', config.fs, 'ro', 'r', 'peaks');
    h_trough = plot_breath_markers(b, 'trough', config.fs, 'bo', 'b', 'troughs');
    title(['FINAL RESPIRATION ' basename newline ...
        'Subject: ' num2str(config.subject) ' | Measurement: ' num2str(config.measure)])
    legend_handles = [h_signal; h_peak; h_trough];
    legend_handles = legend_handles(isgraphics(legend_handles));
    legend_labels = get(legend_handles, 'DisplayName');
    if ischar(legend_labels) || isstring(legend_labels)
        legend_labels = cellstr(legend_labels);
    end
    legend(legend_handles, legend_labels, 'Location', 'best')
    ylabel('Standardized respiration belt amplitude')
    xlabel('Time (seconds)')
    hold off
    save_figure(config, basename)
end

function h = plot_breath_markers(b, marker_name, fs, marker_style, marker_color, display_name)
% PLOT_BREATH_MARKERS Plot breath markers.
%
% Syntax:
%   h = plot_breath_markers(b, marker_name, fs, marker_style, marker_color, display_name)
%
% Inputs:
%   b - Respiratory-cycle or belt-evidence structure.
%   marker_name - Input value `marker_name`.
%   fs - Sampling frequency in hertz.
%   marker_style - Input value `marker_style`.
%   marker_color - Input value `marker_color`.
%   display_name - Input value `display_name`.
%
% Outputs:
%   h - Graphics handle or array.

    idx_field = [marker_name '_idx'];
    time_field = [marker_name '_t'];
    val_field = [marker_name '_val'];

    h = gobjects(0);
    marker_t = [];
    marker_val = [];
    if isfield(b, val_field)
        marker_val = b.(val_field);
        if isfield(b, time_field)
            marker_t = b.(time_field);
        elseif isfield(b, idx_field)
            marker_idx = b.(idx_field);
            marker_t = (marker_idx(:) - 1) / fs;
        end
        marker_t = marker_t(:);
        marker_val = marker_val(:);
    end

    if isempty(marker_t) || isempty(marker_val)
        return;
    end

    h = plot(marker_t, marker_val, marker_style, ...
        'MarkerFaceColor', marker_color, ...
        'DisplayName', display_name);
end
