function events = detect_irregular_breathing(data, breaths_lungs, breaths_diaph, config)
% detect_irregular_breathing
% Label 2 – Irregular Breathing
%
% Definition:
%   Irregular breathing means that durations of consecutive breathing cycles
%   vary unpredictably and without a clear pattern.
%
% Conditions (per 30–60 s segments):
%   - Compute IBI = time between consecutive respiratory peaks.
%   - Compute CoV = std(IBI) / mean(IBI)
%   - Compute RMSSD = sqrt(mean(diff(IBI).^2))
%   - If CoV >= 0.3 OR RMSSD >= 0.5 s -> irregular breathing
%   - Calculated separately for lungs and diaphragm; label positive if either is positive.
%   - No breathing pauses allowed in analyzed segment: exclude segments where any IBI >= 10 s.
%
% Output:
%   events struct array with fields: type, start_idx, end_idx, start_t, end_t

    events = empty_events();

    N = size(data,1);
    t_grid = (0:config.grid_step_sec:(N-1)/config.fs)';  % seconds

    if isempty(breaths_lungs) || isempty(breaths_diaph) || ...
       ~isfield(breaths_lungs, 'peak_t') || ~isfield(breaths_diaph, 'peak_t')
        return;
    end

    % Rolling analysis window length: 30–60s. Use config.IrB.analysis_win_sec if present,
    % otherwise default to 60s.
    if isfield(config, 'IrB') && isfield(config.IrB, 'analysis_win_sec') && ~isempty(config.IrB.analysis_win_sec)
        analysis_win_sec = config.IrB.analysis_win_sec;
    else
        analysis_win_sec = 60;
    end

    % Thresholds
    cov_thr   = 0.3;
    rmssd_thr = 0.5;     % seconds
    pause_thr = 10;      % seconds (no pauses >=10s allowed)

    if isfield(config, 'IrB')
        if isfield(config.IrB, 'cov_thr'),   cov_thr = config.IrB.cov_thr; end
        if isfield(config.IrB, 'rmssd_thr'), rmssd_thr = config.IrB.rmssd_thr; end
        if isfield(config.IrB, 'pause_thr_sec'), pause_thr = config.IrB.pause_thr_sec; end
    end

    irregular_lungs = irregular_condition_on_grid_from_peaks( ...
        breaths_lungs.peak_t, t_grid, analysis_win_sec, cov_thr, rmssd_thr, pause_thr);

    irregular_diaph = irregular_condition_on_grid_from_peaks( ...
        breaths_diaph.peak_t, t_grid, analysis_win_sec, cov_thr, rmssd_thr, pause_thr);

    % Irregular if either belt indicates irregular breathing
    irregular_any = irregular_lungs | irregular_diaph;

    % Convert runs -> events. If you want a minimum duration constraint for IrB, set it here.
    if isfield(config, 'IrB') && isfield(config.IrB, 'min_dur_sec') && ~isempty(config.IrB.min_dur_sec)
        min_dur_sec = config.IrB.min_dur_sec;
    else
        min_dur_sec = 0;  % keep all runs by default
    end

    ev_grid = runs_to_events(irregular_any, 1/config.grid_step_sec, min_dur_sec, 'irregular_breathing');
    events = grid_events_to_sample_events(ev_grid, config.fs, N);

    % Optional plot
    if isfield(config, 'IrB') && isfield(config.IrB, 'do_plot') && config.IrB.do_plot
    
        idx_lungs = find(strcmp(config.data_columns, 'Resp-Lungs'), 1);
        idx_diap  = find(strcmp(config.data_columns, 'Resp-Diaphragm'), 1);
    
        t_raw = (0:size(data,1)-1)/config.fs;
    
        figure('Units','pixels','Position',[100 100 1200 800], 'Visible', config.make_figs_visible); 
        sgtitle(['IRREGULAR BREATHING' newline 'Subject: ' num2str(config.subject) ' | Condition: ' num2str(config.condition)])

        % =========================
        % LUNGS
        % =========================
        subplot(2,1,1); hold on
    
        plot(t_raw, data(:,idx_lungs), 'k')
    
        % Shade irregular regions
        shade_mask_on_axis(t_grid, irregular_lungs)
    
        title('Lungs - Raw Signal with Irregular Mask')
        xlabel('Time (s)')
        ylabel('Amplitude')
        grid on
        hold off
    
    
        % =========================
        % DIAPHRAGM
        % =========================
        subplot(2,1,2); hold on
    
        plot(t_raw, data(:,idx_diap), 'k')
    
        shade_mask_on_axis(t_grid, irregular_diaph)
    
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

function cond = irregular_condition_on_grid_from_peaks(peak_t, t_grid, win_sec, cov_thr, rmssd_thr, pause_thr_sec)
% For each grid time t:
%   - take IBIs from peaks in [t-win_sec, t]
%   - reject window if any IBI >= pause_thr_sec
%   - compute CoV and RMSSD
%   - cond(t)=true if (CoV>=cov_thr) OR (RMSSD>=rmssd_thr)

    cond = false(size(t_grid));
    peak_t = peak_t(:);

    for i = 1:numel(t_grid)
        t = t_grid(i);
        lb = t - win_sec;
        if lb < 0
            continue;  % not enough history for a full 60 s window yet
        end
        % Peaks inside window
        idx = find(peak_t >= lb & peak_t <= t);
        if numel(idx) < 3
            % Need at least ~10 peaks to get >=3 IBIs and stable stats
            continue;
        end

        ibi = diff(peak_t(idx));  % seconds

        % Exclude windows with pauses
        if any(ibi >= pause_thr_sec)
            continue;
        end

        mu = mean(ibi, 'omitnan');
        sd = std(ibi,  0, 'omitnan');  % default normalization
        if ~isfinite(mu) || mu <= 0
            continue;
        end

        cov_val = sd / mu;

        dibi = diff(ibi);
        rmssd_val = sqrt(mean(dibi.^2, 'omitnan'));

        if (isfinite(cov_val) && cov_val >= cov_thr) || (isfinite(rmssd_val) && rmssd_val >= rmssd_thr)
            cond(i) = true;
        end
    end
end
