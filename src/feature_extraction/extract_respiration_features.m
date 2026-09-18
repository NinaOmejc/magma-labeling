function resp_cycles = extract_respiration_features(data, config)
% EXTRACT_RESPIRATION_FEATURES Automatically extract cycles for both belts.
% data is Nsample-by-Nchannel physiological data; config supplies channel
% mappings, sampling rate, and peak settings.
% resp_cycles fields:
%   lungs/diaph - Per-belt cycle structs from extract_respiration_feature.
%   provenance  - review_status plus logical manual_review_performed,
%                 manual_edits_made, and loaded_from_cache flags.

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

    if isfield(config.resp, 'plot_amp_method_comparison') && ...
            config.resp.plot_amp_method_comparison
        plot_amplitude_method_comparison(resp_cycles.lungs, config, 'lungs');
        plot_amplitude_method_comparison(resp_cycles.diaph, config, 'diaph');
    end

    resp_cycles.provenance = struct( ...
        'review_status', 'automatic', ...
        'manual_review_performed', false, ...
        'manual_edits_made', false, ...
        'loaded_from_cache', false);
end

function plot_amplitude_method_comparison(b, config, basename)
% PLOT_AMPLITUDE_METHOD_COMPARISON Compare excursions at shared breath peaks.

    required = {'peak_t', 'amp_exp', 'amp_insp', 'amp_sym'};
    if ~isstruct(b) || ~all(isfield(b, required)) || isempty(b.peak_t)
        return;
    end

    selected = resolve_respiration_amplitude_method(config);
    fig = figure('Units', 'pixels', ...
        'Position', near_fullscreen_figure_position(), ...
        'Visible', config.make_figs_visible, 'Color', 'w');
    ax = axes(fig);
    hold(ax, 'on');
    plot(ax, b.peak_t, b.amp_exp, 'o-', ...
        'DisplayName', 'expiratory/current');
    plot(ax, b.peak_t, b.amp_insp, 's-', ...
        'DisplayName', 'inspiratory');
    plot(ax, b.peak_t, b.amp_sym, 'd-', ...
        'DisplayName', 'symmetric');
    xlabel(ax, 'Breath peak time (seconds)');
    ylabel(ax, 'Standardized respiration belt excursion');
    title(ax, ['RESPIRATION AMPLITUDE METHODS ' basename newline ...
        'Subject: ' num2str(config.subject) ' | Measurement: ' ...
        num2str(config.measure) ' | selected: ' selected]);
    legend(ax, 'Location', 'best');
    grid(ax, 'on');
    hold(ax, 'off');
    save_figure(config, ['respiration_amplitude_methods_' basename]);
end
