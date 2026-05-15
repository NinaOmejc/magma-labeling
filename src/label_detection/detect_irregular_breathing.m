function irregular_events = detect_irregular_breathing(data, breaths_lungs, breaths_diaph, config)
% detect_irregular_breathing
% Label 2 – Irregular Breathing
%
% Definition:
%   Irregular breathing means that durations of consecutive breathing cycles
%   vary unpredictably and without a clear pattern.
%
% Measurements (per 30–60 s segments):
%   - Compute IBI = time between consecutive respiratory peaks.
%   - Compute CoV = std(IBI) / mean(IBI)
%   - Compute RMSSD = sqrt(mean(diff(IBI).^2))
%   - If CoV >= 0.3 OR RMSSD >= 0.5 s -> irregular breathing
%   - Calculated separately for lungs and diaphragm; label positive if either is positive.
%   - No breathing pauses allowed in analyzed segment: exclude segments where any IBI >= 10 s.
%
% Output:
%   events struct array with fields: type, start_idx, end_idx, start_t, end_t

    irregular_events = empty_events();

    N = size(data,1);
    t_grid = (0:config.grid_step_sec:(N-1)/config.fs)';  % seconds

    lungs_broken = isfield(config,'problems') && isfield(config.problems,'subjects_with_broken_lung_belt') && ...
        any(config.subject == config.problems.subjects_with_broken_lung_belt);
    lungs_valid = is_valid_breath_signal(breaths_lungs, false) && ~lungs_broken;
    diaph_valid = is_valid_breath_signal(breaths_diaph, false);

    if ~lungs_valid && ~diaph_valid
        return;
    end

    % Thresholds
    cov_thr   = 0.3;
    rmssd_thr = 0.0;     % seconds
    pause_thr = 10;      % seconds (no pauses >=10s allowed)
    analysis_win_sec = 60;
    min_dur_sec = 0;  % keep all runs by default
    do_plot = false;
    
    if isfield(config, 'IrB')
        if isfield(config.IrB, 'cov_thr'),   cov_thr = config.IrB.cov_thr; end
        if isfield(config.IrB, 'rmssd_thr'), rmssd_thr = config.IrB.rmssd_thr; end
        if isfield(config.IrB, 'pause_thr_sec'), pause_thr = config.IrB.pause_thr_sec; end
        if isfield(config.IrB, 'analysis_win_sec'), analysis_win_sec = config.IrB.analysis_win_sec; end
        if isfield(config.IrB, 'min_dur_sec'), min_dur_sec = config.IrB.min_dur_sec; end
        if isfield(config.IrB, 'do_plot'), do_plot = config.IrB.do_plot; end
    end

    irregular_mask_lungs = false(size(t_grid));
    if lungs_valid
        irregular_mask_lungs = compute_irregular_breathing_mask( ...
            breaths_lungs, t_grid, analysis_win_sec, cov_thr, rmssd_thr, pause_thr);
    end

    irregular_mask_diaph = false(size(t_grid));
    if diaph_valid
        irregular_mask_diaph = compute_irregular_breathing_mask( ...
            breaths_diaph, t_grid, analysis_win_sec, cov_thr, rmssd_thr, pause_thr);
    end

    % Convert mask -> events.
    irregular_ev_grid_lungs = runs_to_events(irregular_mask_lungs, 1/config.grid_step_sec, min_dur_sec, 'irregular_breathing_lungs');
    irregular_events_lungs = grid_events_to_sample_events(irregular_ev_grid_lungs, config.fs, N);

    irregular_events_on_grid_diaph = runs_to_events(irregular_mask_diaph, 1/config.grid_step_sec, min_dur_sec, 'irregular_breathing_diaph');
    irregular_events_diaph = grid_events_to_sample_events(irregular_events_on_grid_diaph, config.fs, N);
    
    irregular_events = merge_events({irregular_events_lungs, irregular_events_diaph});

    % Optional plot
    if do_plot
    
        idx_lungs = find(strcmp(config.data_columns, 'Resp-Lungs'), 1);
        idx_diaph  = find(strcmp(config.data_columns, 'Resp-Diaphragm'), 1);
        
        figure('Units','pixels','Position', near_fullscreen_figure_position(), 'Visible', config.make_figs_visible); 
        sgtitle(['IRREGULAR BREATHING' newline 'Subject: ' num2str(config.subject) ' | Measurement: ' num2str(config.measure)])

        % =========================
        % LUNGS
        % =========================
        subplot(2,1,1); hold on
    
        plot(config.times, data(:,idx_lungs), 'k')
    
        % Shade irregular regions
        shade_mask_on_axis(t_grid, irregular_mask_lungs)
    
        title('Lungs - Raw Signal with Irregular Mask')
        xlabel('Time (s)')
        ylabel('Amplitude')
        grid on
        hold off
    
    
        % =========================
        % DIAPHRAGM
        % =========================
        subplot(2,1,2); hold on
    
        plot(config.times, data(:,idx_diaph), 'k')
    
        shade_mask_on_axis(t_grid, irregular_mask_diaph)
    
        title('Diaphragm - Raw Signal with Irregular Mask')
        xlabel('Time (s)')
        ylabel('Amplitude')
        grid on
        hold off

        ax = findall(gcf,'Type','axes');
        ax = ax(arrayfun(@(a) ~strcmp(a.Tag,'legend'), ax));
        linkaxes(ax,'x');          % tie x-zoom/pan
        xlim(ax(1), [0 t_grid(end)]);     % or whatever common range you want
   
        save_figure(config, 'irregular_breathing');
    end
end

% ===================== helper functions =====================
function irregular_mask = compute_irregular_breathing_mask(breaths, t_grid, win_sec, ...
                                                           cov_thr, rmssd_thr, pause_thr_sec)
%IRREGULAR_CONDITION_ON_GRID_FROM_BREATHS
%
% Requires:
%   breaths.peak_t   peak times in seconds
%   breaths.ibi      inter-breath intervals in seconds
%
% For each grid time t:
%   - take IBIs in [t-win_sec, t]
%   - reject window if any IBI >= pause_thr_sec
%   - compute CoV = std(IBI) / mean(IBI)
%   - optionally compute RMSSD if rmssd_thr > 0
%   - mark the whole window true if irregular

    irregular_mask = false(size(t_grid));

    if isempty(breaths) || ~isstruct(breaths) || ~isfield(breaths, 'peak_t') || ~isfield(breaths, 'ibi') || ~breaths.ok
        return
    end

    peak_t = breaths.peak_t(:);
    ibi    = breaths.ibi(:);

    % IBI(i) corresponds to interval peak_t(i) -> peak_t(i+1)
    % Assign IBI time to the second peak.
    ibi_t = peak_t(2:end);

    if numel(ibi) ~= numel(ibi_t)
        error('breaths.ibi must have length numel(breaths.peak_t)-1.');
    end

    valid = isfinite(ibi) & ibi > 0 & isfinite(ibi_t);
    ibi = ibi(valid);
    ibi_t = ibi_t(valid);

    if numel(ibi) < 5
        return
    end

    use_rmssd = isfinite(rmssd_thr) && rmssd_thr > 0;

    for i = 1:numel(t_grid)
        t = t_grid(i);
        lb = t - win_sec;

        if lb < 0
            continue
        end

        in_win = ibi_t >= lb & ibi_t <= t;
        ibi_win = ibi(in_win);

        if numel(ibi_win) < 5
            continue
        end

        % Exclude windows with breathing pauses
        if any(ibi_win >= pause_thr_sec)
            continue
        end

        mu = mean(ibi_win, 'omitnan');
        sd = std(ibi_win, 0, 'omitnan');

        if ~isfinite(mu) || mu <= 0 || ~isfinite(sd)
            continue
        end

        cov_val = sd / mu;

        is_irregular = cov_val >= cov_thr;

        % If rmssd_thr == 0, RMSSD is ignored.
        if use_rmssd
            dibi = diff(ibi_win);

            if ~isempty(dibi)
                rmssd_val = sqrt(mean(dibi.^2, 'omitnan'));

                is_irregular = is_irregular || ...
                    (isfinite(rmssd_val) && rmssd_val >= rmssd_thr);
            end
        end

        % Mark the whole analysis window, not only the endpoint.
        if is_irregular
            irregular_mask(t_grid >= lb & t_grid <= t) = true;
        end
    end
end
