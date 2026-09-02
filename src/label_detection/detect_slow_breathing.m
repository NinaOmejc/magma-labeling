function events = detect_slow_breathing(data, phys_feat, config)
% detect_slow_breathing
% Label 3 – Slow Breathing (Bradypnea)
%
% Conditions:
%   - Mean RR <= 10 bpm sustained for >= 30 s.
%   - 60 s windows analyzed.
%   - Computed separately for lungs and diaphragm; positive if either is positive.
%
% Notes:
%   1) Optionally distinguish "slow+deep" vs "slow+shallow" using amplitude ratio.
%   2) Optionally mark "slow breathing with desaturation" if SpO2 drop >=3% overlaps
%      slow breathing (with optional delay buffer).
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
        fprintf('Skipping slowB detection: no valid respiratory belt with usable breath timing.\n');
        return;
    end

    % ----------------------------
    % Config defaults
    % ----------------------------
    rr_thr_bpm       = 10;
    min_dur_sec      = 30;

    classify_depth   = true;      % slow+shallow vs slow+deep

    mark_desat       = true;
    desat_association_delay_sec = get_config_value(config, 'spo2', 'desat_association_delay_sec', 10);
    plot_rr_step_sec = 15;

    if isfield(config, 'SlB')
        if isfield(config.SlB, 'rr_thr_bpm'),       rr_thr_bpm       = config.SlB.rr_thr_bpm; end
        if isfield(config.SlB, 'min_dur_sec'),      min_dur_sec      = config.SlB.min_dur_sec; end

        if isfield(config.SlB, 'classify_depth'),   classify_depth   = config.SlB.classify_depth; end
        if isfield(config.SlB, 'mark_desat'),       mark_desat       = config.SlB.mark_desat; end
        if isfield(config.SlB, 'plot_rr_step_sec'), plot_rr_step_sec = config.SlB.plot_rr_step_sec; end
    end

    % ----------------------------
    % Slow RR endpoint condition on grid (lungs/diaph). The metric plotted
    % at time t uses the configured slow-rate window in phys_feat, so the detection
    % mask follows that endpoint trace instead of backfilling the window.
    % ----------------------------
    slow_lungs = false(size(t_grid));
    rr_lungs = nan(size(t_grid));
    if lungs_valid
        rr_lungs = lungs.rate_slow_window_bpm;
        slow_lungs = isfinite(rr_lungs) & rr_lungs <= rr_thr_bpm;
    end

    slow_diaph = false(size(t_grid));
    rr_diaph = nan(size(t_grid));
    if diaph_valid
        rr_diaph = diaph.rate_slow_window_bpm;
        slow_diaph = isfinite(rr_diaph) & rr_diaph <= rr_thr_bpm;
    end

    % Sustain the endpoint RR condition before creating events.
    [events_lungs, slow_lungs] = sustained_condition_to_events( ...
        slow_lungs, t_grid, config.fs, N, min_dur_sec, 'slow_breathing_lungs');
    [events_diaph, slow_diaph] = sustained_condition_to_events( ...
        slow_diaph, t_grid, config.fs, N, min_dur_sec, 'slow_breathing_diaph');

    events = merge_events({events_lungs, events_diaph});

    % ----------------------------
    % Optional: classify slow+shallow vs slow+deep using amplitude ratio
    % ----------------------------
    if classify_depth && (lungs_amp_valid || diaph_amp_valid)
        shallow_amp = false(size(t_grid));
        if lungs_amp_valid
            shallow_amp = shallow_amp | lungs.shallow_amplitude_mask;
        end
        if diaph_amp_valid
            shallow_amp = shallow_amp | diaph.shallow_amplitude_mask;
        end

        % Temporary Phase-3 compatibility block. Depth will become an
        % independent label in Phase 4; current saved subtype strings remain.
        for e = 1:numel(events)
            g0 = max(1, round(events(e).start_t / config.grid_step_sec) + 1);
            g1 = min(numel(t_grid), round(events(e).end_t   / config.grid_step_sec) + 1);
            if g0 <= g1
                frac_shallow = mean(shallow_amp(g0:g1));
                belt_suffix = event_belt_suffix(events(e).type);
                if frac_shallow >= 0.5
                    events(e).type = ['slow_breathing_shallow' belt_suffix];
                else
                    events(e).type = ['slow_breathing_deep' belt_suffix];
                end
            end
        end
    end

    % ----------------------------
    % Optional: mark slow breathing WITH desaturation
    % ----------------------------
    if mark_desat && isfield(phys_feat, 'spo2') && ...
            isfield(phys_feat.spo2, 'desaturation_events')

        % Temporary compatibility only. Desaturation is independent
        % evidence in phys_feat and will not be embedded after Phase 4.
        desat_events = phys_feat.spo2.desaturation_events;
    
        % Allow SpO2 drops that start shortly after the breathing event.
        desat_events = expand_events_for_delayed_overlap(desat_events, desat_association_delay_sec);
    
        % If a slow event overlaps any desat event -> relabel with "_desat"
        for e = 1:numel(events)
            if events_overlap_any(events(e), desat_events)
                events(e).type = [events(e).type '_desat'];
            end
        end
    end

    % ----------------------------
    % Optional plot (raw + shaded slow mask)
    % ----------------------------
    if isfield(config, 'SlB') && isfield(config.SlB, 'do_plot') && config.SlB.do_plot
        opts = struct( ...
            'figure_title', ['SLOW BREATHING' newline 'Subject: ' num2str(config.subject) ' | Measurement: ' num2str(config.measure)], ...
            'event_name', 'Slow breathing', ...
            'metric_title', 'Mean breaths/min used for slow detection', ...
            'metric_detail', sprintf('%g s held median', plot_rr_step_sec), ...
            'metric_ylabel', 'Breaths/min', ...
            'threshold', rr_thr_bpm, ...
            'threshold_label', sprintf('Threshold: <= %g breaths/min', rr_thr_bpm), ...
            'plot_step_sec', plot_rr_step_sec, ...
            'min_ymax', rr_thr_bpm + 10, ...
            'ymax_padding', 5, ...
            'output_name', 'slow_breathing');
        plot_belt_diagnostic_figure(data, config, t_grid, slow_lungs, slow_diaph, rr_lungs, rr_diaph, opts);
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
