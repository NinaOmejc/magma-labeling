function events = detect_rapid_breathing(data, phys_feat, config)
% detect_rapid_breathing
% Label 4 – Rapid Breathing (Tachypnea)
%
% Criteria:
%   - Mean RR >= 20 breaths/min sustained for >= 30 s.
%   - 30-second windows analyzed by default.
%   - Computed separately for lungs and diaphragm; positive if either is positive.
%
% Notes:
%   1) rapid_shallow = rapid breathing + shallow amplitude band.
%   2) rapid_deep    = rapid breathing + 20-35% amplitude increase from baseline.
%   3) rapid_desat   = rapid breathing + SpO2 desaturation, allowing delayed SpO2.
%   4) rapid         = rapid breathing without shallow/deep/desat subtype evidence.
% Detector grids map to master samples using config.fs.

    events = empty_events();

    N = size(data,1);
    t_grid = phys_feat.resp.time_sec;
    lungs = phys_feat.resp.lungs;
    diaph = phys_feat.resp.diaph;
    lungs_valid = lungs.available;
    diaph_valid = diaph.available;
    lungs_amp_valid = lungs.session_amplitude_available;
    diaph_amp_valid = diaph.session_amplitude_available;

    if ~lungs_valid && ~diaph_valid
        fprintf('Skipping rapidB detection: no valid respiratory belt with usable breath timing.\n');
        return;
    end

    rr_thr_bpm = get_config_value(config, 'RaB', 'rr_thr_bpm', 20);
    min_dur_sec = get_config_value(config, 'RaB', 'min_dur_sec', 30);
    classify_depth = get_config_value(config, 'RaB', 'classify_depth', true);
    subtype_min_overlap_frac = 0.5;
    mark_desat = get_config_value(config, 'RaB', 'mark_desat', true);
    desat_association_delay_sec = get_config_value(config, 'spo2', 'desat_association_delay_sec', 10);
    plot_rr_step_sec = get_config_value(config, 'RaB', 'plot_rr_step_sec', 15);
    subtype_min_overlap_frac = get_config_value(config, 'RaB', 'subtype_min_overlap_frac', subtype_min_overlap_frac);

    % RR endpoint condition on grid. Keep the event mask aligned with the
    % plotted metric instead of marking the whole trailing analysis window.
    rapid_lungs_rr = false(size(t_grid));
    rr_lungs = nan(size(t_grid));
    if lungs_valid
        rr_lungs = lungs.rate_rapid_window_bpm;
        rapid_lungs_rr = isfinite(rr_lungs) & rr_lungs >= rr_thr_bpm;
    end

    rapid_diaph_rr = false(size(t_grid));
    rr_diaph = nan(size(t_grid));
    if diaph_valid
        rr_diaph = diaph.rate_rapid_window_bpm;
        rapid_diaph_rr = isfinite(rr_diaph) & rr_diaph >= rr_thr_bpm;
    end

    [rapid_events_lungs, rapid_lungs] = sustained_condition_to_events( ...
        rapid_lungs_rr, t_grid, config.fs, N, min_dur_sec, 'rapid_lungs');
    [rapid_events_diaph, rapid_diaph] = sustained_condition_to_events( ...
        rapid_diaph_rr, t_grid, config.fs, N, min_dur_sec, 'rapid_diaph');
    rapid_events = merge_events({rapid_events_lungs, rapid_events_diaph});
    if isempty(rapid_events)
        return;
    end

    shallow_amp = false(size(t_grid));
    deep_amp = false(size(t_grid));
    if classify_depth && (lungs_amp_valid || diaph_amp_valid)
        if lungs_amp_valid
            shallow_amp = shallow_amp | lungs.shallow_amplitude_mask;
            deep_amp = deep_amp | lungs.deep_amplitude_mask;
        end
        if diaph_amp_valid
            shallow_amp = shallow_amp | diaph.shallow_amplitude_mask;
            deep_amp = deep_amp | diaph.deep_amplitude_mask;
        end
    end

    desat_events = empty_events();
    if mark_desat && isfield(phys_feat, 'spo2') && ...
            isfield(phys_feat.spo2, 'desaturation_events')
        % Temporary saved-subtype compatibility. SpO2 remains an
        % independent evidence stream and this tagging is removed in Phase 4.
        desat_events = expand_events_for_delayed_overlap( ...
            phys_feat.spo2.desaturation_events, desat_association_delay_sec);
    end

    events = tag_rapid_events(rapid_events, shallow_amp, deep_amp, desat_events, ...
        t_grid, config.grid_step_sec, subtype_min_overlap_frac);

    % ----------------------------
    % Optional debug plot (raw + shaded rapid mask)
    % ----------------------------
    if isfield(config, 'RaB') && isfield(config.RaB, 'do_plot') && config.RaB.do_plot
        opts = struct( ...
            'figure_title', ['RAPID BREATHING' newline 'Subject: ' num2str(config.subject) ' | Measurement: ' num2str(config.measure)], ...
            'event_name', 'Rapid breathing', ...
            'metric_title', 'Mean breaths/min used for rapid detection', ...
            'metric_detail', sprintf('%g s held median', plot_rr_step_sec), ...
            'metric_ylabel', 'Breaths/min', ...
            'threshold', rr_thr_bpm, ...
            'threshold_label', sprintf('Threshold: >= %g breaths/min', rr_thr_bpm), ...
            'plot_step_sec', plot_rr_step_sec, ...
            'min_ymax', rr_thr_bpm + 10, ...
            'ymax_padding', 5, ...
            'output_name', 'rapid_breathing');
        plot_belt_diagnostic_figure(data, config, t_grid, rapid_lungs, rapid_diaph, rr_lungs, rr_diaph, opts);
    end
end

function events = tag_rapid_events(rapid_events, shallow_amp, deep_amp, desat_events, t_grid, grid_step_sec, min_frac)
    events = empty_events();

    for e = 1:numel(rapid_events)
        g0 = max(1, floor(rapid_events(e).start_t / grid_step_sec) + 1);
        g1 = min(numel(t_grid), ceil(rapid_events(e).end_t / grid_step_sec) + 1);

        labels = {};
        belt_suffix = event_belt_suffix(rapid_events(e).type);
        if g0 <= g1 && mean(shallow_amp(g0:g1)) >= min_frac
            labels{end+1} = ['rapid_shallow' belt_suffix]; %#ok<AGROW>
        end
        if g0 <= g1 && mean(deep_amp(g0:g1)) >= min_frac
            labels{end+1} = ['rapid_deep' belt_suffix]; %#ok<AGROW>
        end
        if ~isempty(desat_events) && events_overlap_any(rapid_events(e), desat_events)
            labels{end+1} = ['rapid_desat' belt_suffix]; %#ok<AGROW>
        end
        if isempty(labels)
            labels = {['rapid' belt_suffix]};
        end

        for k = 1:numel(labels)
            ev = rapid_events(e);
            ev.type = labels{k};
            events(end+1,1) = ev; %#ok<AGROW>
        end
    end
end

function suffix = event_belt_suffix(raw_type)
    suffix = '';
    s = lower(string(raw_type));
    if contains(s, 'lungs')
        suffix = '_lungs';
    elseif contains(s, 'diaph')
        suffix = '_diaph';
    end
end
