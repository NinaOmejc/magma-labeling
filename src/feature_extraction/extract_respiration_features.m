function resp_feat = extract_respiration_features(data, config)
% Extract respiratory features using master sample indices at config.fs.
    
    if ~isfield(config, 'channels')
        config = resolve_signal_channels(config);
    end
    idx_lungs = config.channels.lungs_idx;
    idx_diaph = config.channels.diaph_idx;

    % ---- breath series (peaks + per-breath amplitudes) ----
    resp_feat = struct();
    if ~isempty(idx_lungs)
        resp_feat.lungs = extract_respiration_feature(data(:, idx_lungs), config, 'lungs');
    else
        resp_feat.lungs = empty_respiration_feature('lungs');
    end
    if ~isempty(idx_diaph)
        resp_feat.diaph = extract_respiration_feature(data(:, idx_diaph), config, 'diaph');
    else
        resp_feat.diaph = empty_respiration_feature('diaph');
    end

    if isfield(config.resp, 'manual_control') && config.resp.manual_control
        edit_lungs = is_editable_resp_signal(resp_feat.lungs) && ~is_lung_belt_ignored(config);
        edit_diaph = is_editable_resp_signal(resp_feat.diaph);

        if edit_lungs || edit_diaph
            [resp_feat.lungs, resp_feat.diaph] = manual_edit_respiration_features(data, resp_feat.lungs, resp_feat.diaph, config);
            if isfield(config.resp, 'do_plot') && config.resp.do_plot
                if edit_lungs
                    save_final_respiration_feature_figure(resp_feat.lungs, config, 'lungs');
                end
                if edit_diaph
                    save_final_respiration_feature_figure(resp_feat.diaph, config, 'diaph');
                end
            end
        else
            warning('MAGMA:Respiration:ManualSkipped', ...
                'Manual breath editing requires at least one usable respiratory belt signal and was skipped.');
        end
    end
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
