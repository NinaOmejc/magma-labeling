function baseline = add_rolling_resp_baseline(baseline, resp_feat, N, config)
% add_rolling_resp_baseline
% Adds time-varying respiratory amplitude references to baseline.

if ~isfield(config, 'rolling_baseline') || ~config.rolling_baseline.enabled
    return;
end

t_grid = (0:config.grid_step_sec:(N-1)/config.new_fs)';

win_sec = config.rolling_baseline.win_sec;
lag_sec = config.rolling_baseline.lag_sec;
min_breaths = config.rolling_baseline.min_breaths;
method = config.rolling_baseline.method;

baseline.rolling = struct();
baseline.rolling.t_grid = t_grid;

baseline.rolling.lungs_amp_ref = rolling_amp_ref( ...
    resp_feat.lungs, t_grid, win_sec, lag_sec, min_breaths, ...
    method, baseline.lungs_amp_ref);

baseline.rolling.diaph_amp_ref = rolling_amp_ref( ...
    resp_feat.diaph, t_grid, win_sec, lag_sec, min_breaths, ...
    method, baseline.diaph_amp_ref);


%%%%%%%%%%%%%
% PLOTTING 

if config.rolling_baseline.do_plot
    t_roll = baseline.rolling.t_grid;
    x_label_extra = 'Rolling baseline shown at detector time';
    
    fig = figure('Units','pixels','Position', near_fullscreen_figure_position(), 'Visible', config.make_figs_visible, 'Color', 'w');
    
    tiledlayout(2, 1, 'TileSpacing', 'compact', 'Padding', 'compact');
    
    % -------------------------
    % Lungs
    % -------------------------
    nexttile;
    
    if isfield(resp_feat.lungs, 'peak_t') && isfield(resp_feat.lungs, 'amp') && ...
            ~isempty(resp_feat.lungs.peak_t) && ~isempty(resp_feat.lungs.amp)
    
        plot(resp_feat.lungs.peak_t, resp_feat.lungs.amp, '.-');
        hold on;
    else
        hold on;
        text(0.5, 0.5, 'No lung breath amplitudes available', ...
            'Units', 'normalized', 'HorizontalAlignment', 'center');
    end
    
    plot(t_roll, baseline.rolling.lungs_amp_ref, 'LineWidth', 1.5);
    yline(baseline.lungs_amp_ref, '--', 'LineWidth', 1.2);
    
    xlabel('Time [s]');
    ylabel('Lung amplitude');
    title(sprintf('Lungs rolling baseline | win = %g s, lag = %g s, min breaths = %d, method = %s', ...
        config.rolling_baseline.win_sec, ...
        config.rolling_baseline.lag_sec, ...
        config.rolling_baseline.min_breaths, ...
        config.rolling_baseline.method), ...
        'Interpreter', 'none');
    
    if isfield(resp_feat.lungs, 'peak_t') && isfield(resp_feat.lungs, 'amp') && ...
        ~isempty(resp_feat.lungs.peak_t) && ~isempty(resp_feat.lungs.amp)

        legend('Breath amplitudes', 'Rolling baseline', 'Static baseline', ...
                'Location', 'best');
    end
    grid on;
    
    % -------------------------
    % Diaphragm
    % -------------------------
    nexttile;
    
    if isfield(resp_feat.diaph, 'peak_t') && isfield(resp_feat.diaph, 'amp') && ...
            ~isempty(resp_feat.diaph.peak_t) && ~isempty(resp_feat.diaph.amp)
    
        plot(resp_feat.diaph.peak_t, resp_feat.diaph.amp, '.-');
        hold on;
    else
        hold on;
        text(0.5, 0.5, 'No diaphragm breath amplitudes available', ...
            'Units', 'normalized', 'HorizontalAlignment', 'center');
    end
    
    plot(t_roll, baseline.rolling.diaph_amp_ref, 'LineWidth', 1.5);
    yline(baseline.diaph_amp_ref, '--', 'LineWidth', 1.2);
    
    xlabel(sprintf('Time [s] — %s', x_label_extra));
    ylabel('Diaphragm amplitude');
    title('Diaphragm rolling baseline');
    legend('Breath amplitudes', 'Rolling baseline', 'Static baseline', ...
        'Location', 'best');
    grid on;

    set(fig, 'Visible', config.make_figs_visible);
    
    save_figure(config, 'rolling_baseline')
end
end


function ref = rolling_amp_ref(breaths, t_grid, win_sec, lag_sec, min_breaths, method, fallback_ref)
    
    ref = nan(size(t_grid));
    
    if isempty(breaths) || ~isstruct(breaths) || ~isfield(breaths, 'peak_t') || ...
            ~isfield(breaths, 'amp') || ~isfield(breaths, 'ok') || ~breaths.ok
        ref(:) = fallback_ref;
        return;
    end
    
    peak_t = breaths.peak_t(:);
    amp = breaths.amp(:);
    
    L = min(numel(peak_t), numel(amp));
    peak_t = peak_t(1:L);
    amp = amp(1:L);
    
    valid = isfinite(peak_t) & isfinite(amp) & amp > 0;
    peak_t = peak_t(valid);
    amp = amp(valid);
    
    for i = 1:numel(t_grid)
        t = t_grid(i);
    
        t2 = t - lag_sec;
        t1 = t2 - win_sec;
    
        if t1 <= 0
            ref(i) = NaN;
            continue;
        end
    
        in_win = peak_t >= t1 & peak_t <= t2;
        amps = amp(in_win);
    
        if numel(amps) < min_breaths
            ref(i) = NaN;
            continue;
        end
    
        switch lower(method)
            case 'median'
                ref(i) = median(amps, 'omitnan');
            case 'p75'
                ref(i) = prctile(amps, 75);
            otherwise
                error('Unknown rolling baseline method: %s', method);
        end
    end
    
    
    % Replace early NaNs with first valid rolling baseline point
    valid_ref = isfinite(ref) & ref > 0;
    
    if any(valid_ref)
        first_valid_idx = find(valid_ref, 1, 'first');
        first_valid_val = ref(first_valid_idx);
    
        ref(1:first_valid_idx-1) = first_valid_val;
    
        for k = first_valid_idx+1:numel(ref)
            if ~isfinite(ref(k)) || ref(k) <= 0
                ref(k) = ref(k-1);
            end
        end
    else
        ref(:) = fallback_ref;
    end
    
    bad = ~isfinite(ref) | ref <= 0;
    ref(bad) = fallback_ref;

end
