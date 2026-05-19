function resp_feat = extract_respiration_features(data, config)
    
    idx_lungs = find(strcmp(config.data_columns, 'Resp-Lungs'), 1);
    idx_diaph  = find(strcmp(config.data_columns, 'Resp-Diaphragm'), 1);

    % ---- breath series (peaks + per-breath amplitudes) ----
    resp_feat = struct();
    resp_feat.lungs = extract_respiration_feature(data(:, idx_lungs), config, 'lungs');
    resp_feat.diaph = extract_respiration_feature(data(:, idx_diaph), config, 'diaph');

    if isfield(config.resp, 'manual_control') && config.resp.manual_control
        [resp_feat.lungs, resp_feat.diaph] = manual_edit_respiration_features(data, resp_feat.lungs, resp_feat.diaph, config);
        if isfield(config.resp, 'do_plot') && config.resp.do_plot
            save_final_respiration_feature_figure(resp_feat.lungs, config, 'lungs');
            save_final_respiration_feature_figure(resp_feat.diaph, config, 'diaph');
        end
    end
    
    if ~ismember(config.subject, config.problems.subjects_with_broken_lung_belt)
        check_normalities(resp_feat.lungs, config);
    end
    check_normalities(resp_feat.diaph, config);
end

function save_final_respiration_feature_figure(b, config, basename)
% Save the post-GUI respiration feature figure, overwriting the pre-GUI one.

    if ~isfield(b, 'x0') || isempty(b.x0)
        return;
    end

    x = b.x0(:);
    t = (0:numel(x)-1) / config.new_fs;

    figure('Units','pixels','Position', near_fullscreen_figure_position(), 'Visible', config.make_figs_visible);
    hold on
    h_signal = plot(t, x, 'DisplayName', 'x0');
    h_peak = plot_breath_markers(b, 'peak', config.new_fs, 'ro', 'r', 'peaks');
    h_trough = plot_breath_markers(b, 'trough', config.new_fs, 'bo', 'b', 'troughs');
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
