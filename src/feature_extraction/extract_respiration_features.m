function [b_l, b_d] = extract_respiration_features(data, config)
    
    idx_lungs = find(strcmp(config.data_columns, 'Resp-Lungs'), 1);
    idx_diaph  = find(strcmp(config.data_columns, 'Resp-Diaphragm'), 1);

    % ---- breath series (peaks + per-breath amplitudes) ----
    b_l = extract_respiration_feature(data(:, idx_lungs), config, 'lungs');
    b_d = extract_respiration_feature(data(:, idx_diaph), config, 'diaph');

    if isfield(config.resp, 'manual_control') && config.resp.manual_control
        [b_l, b_d] = manual_edit_respiration_features(data, b_l, b_d, config);
        if isfield(config.resp, 'do_plot') && config.resp.do_plot
            save_final_respiration_feature_figure(b_l, config, 'lungs');
            save_final_respiration_feature_figure(b_d, config, 'diaph');
        end
    end
    
    if ~ismember(config.subject, config.problems.subjects_with_broken_lung_belt)
        check_normalities(b_l, config);
    end
    check_normalities(b_d, config);
end

function save_final_respiration_feature_figure(b, config, basename)
% Save the post-GUI respiration feature figure, overwriting the pre-GUI one.

    if ~isfield(b, 'x0') || isempty(b.x0)
        return;
    end

    x = b.x0(:);
    t = (0:numel(x)-1) / config.fs;

    figure('Units','pixels','Position', near_fullscreen_figure_position(), 'Visible', config.make_figs_visible);
    hold on
    plot(t, x)
    plot_breath_markers(b, 'peak', config.fs, 'ro', 'r');
    plot_breath_markers(b, 'trough', config.fs, 'bo', 'b');
    title(['FINAL RESPIRATION ' basename newline ...
        'Subject: ' num2str(config.subject) ' | Measurement: ' num2str(config.measure)])
    legend('x0', 'peaks', 'troughs')
    ylabel('Standardized respiration belt amplitude')
    xlabel('Time (seconds)')
    hold off
    save_figure(config, basename)
end

function plot_breath_markers(b, marker_name, fs, marker_style, marker_color)
    idx_field = [marker_name '_idx'];
    time_field = [marker_name '_t'];
    val_field = [marker_name '_val'];

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

    plot(marker_t, marker_val, marker_style, 'MarkerFaceColor', marker_color)
end
