function shallow_events = detect_shallow_breathing(data, baseline, breaths_lungs, breaths_diaph, spo2_feat, config)
% detect_shallow_breathing
% Event-based detection of shallow breathing episodes (Label 1).
%
% Criteria (Labels.docx):
%   - Clear reduction in amplitude of respiratory belts (lungs + diaphragm),
%     without complete disappearance, with preserved or increased RR.
%   - Amplitude reduction: 20–35% of reference amplitude (60 s analysis windows).
%   - Duration: sustained >= 30 s.
%   - No desaturation: SpO2 < 90 OR SpO2 drop >= 3–4% below baseline (baseline from first 30–60 s).

    % ---- indices ---
    N = size(data,1);
    t_grid = (0:config.grid_step_sec:(N-1)/config.fs)';  % seconds
    lungs_broken = isfield(config,'problems') && isfield(config.problems,'subjects_with_broken_lung_belt') && ...
        any(config.subject == config.problems.subjects_with_broken_lung_belt);
    lungs_valid = is_valid_breath_signal(breaths_lungs, true) && ~lungs_broken;
    diaph_valid = is_valid_breath_signal(breaths_diaph, true);

    if ~lungs_valid && ~diaph_valid
        shallow_events = empty_events();
        return;
    end

    % ---- shallow condition on grid  ----
    ref_lungs = get_resp_ref_on_grid(baseline, 'lungs', t_grid);
    ref_diaph = get_resp_ref_on_grid(baseline, 'diaph', t_grid);

    shallow_mask_lungs = false(size(t_grid));
    if lungs_valid
        shallow_mask_lungs = compute_shallow_breathing_mask( ...
            breaths_lungs, t_grid, config.ShB.min_dur_sec, ...
            ref_lungs, config.ShB.amp_ratio_low, config.ShB.amp_ratio_high);
    end

    shallow_mask_diaph = false(size(t_grid));
    if diaph_valid
        shallow_mask_diaph = compute_shallow_breathing_mask( ...
            breaths_diaph, t_grid, config.ShB.min_dur_sec, ...
            ref_diaph, config.ShB.amp_ratio_low, config.ShB.amp_ratio_high);
    end

    % ---- no-desaturation condition on grid ----
    desat_mask = false(size(t_grid));
    if exist('spo2_feat','var') && ~isempty(spo2_feat) && isfield(spo2_feat, 'desat_events')
        desat_mask = get_desaturation_mask(spo2_feat.desat_events, t_grid);
    end

    exclude_desat = true;
    if isfield(config, 'ShB') && isfield(config.ShB, 'exclude_desat')
        exclude_desat = config.ShB.exclude_desat;
    end
    no_desat = ~desat_mask | ~exclude_desat;

    % final condition (grid)
    shallow_mask_lungs_final = shallow_mask_lungs & no_desat;
    shallow_mask_diaph_final = shallow_mask_diaph & no_desat;
    
    % convert grid runs -> events (>=30 s)
    shallow_ev_grid_lungs = runs_to_events(shallow_mask_lungs_final, 1/config.grid_step_sec, config.ShB.min_dur_sec, 'shallow_breathing_lungs');
    shallow_events_lungs = grid_events_to_sample_events(shallow_ev_grid_lungs, config.fs, N);

    shallow_events_on_grid_diaph = runs_to_events(shallow_mask_diaph_final, 1/config.grid_step_sec, config.ShB.min_dur_sec, 'shallow_breathing_diaph');
    shallow_events_diaph = grid_events_to_sample_events(shallow_events_on_grid_diaph, config.fs, N);
    
    shallow_events = merge_events({shallow_events_lungs, shallow_events_diaph});
    % shallow_mask = events_to_sample_mask(events, N, config.fs);
    
    % add a figure
    if config.ShB.do_plot

        ratio_low  = config.ShB.amp_ratio_low;
        ratio_high = config.ShB.amp_ratio_high;
        rb_enabled = isfield(config,'rolling_baseline') && isfield(config.rolling_baseline,'enabled') && config.rolling_baseline.enabled;
        if rb_enabled
            rb_win = config.rolling_baseline.win_sec;
            rb_lag = config.rolling_baseline.lag_sec;
            ref_txt = ['Rolling amp ref: win=' num2str(rb_win) 's, lag=' num2str(rb_lag) 's'];
        else
            ref_txt = 'Static amp ref';
        end
        
        figure('Units','pixels','Position', near_fullscreen_figure_position(), 'Visible', config.make_figs_visible); 
        % ----------------------
        % Subplot 1: Lungs
        % ----------------------
        subplot(3,1,1)
        hold on
        lower_l = ratio_low  * ref_lungs;
        upper_l = ratio_high * ref_lungs;
        valid_l = isfinite(t_grid) & isfinite(lower_l) & isfinite(upper_l) & upper_l >= lower_l;
        if any(valid_l)
            patch([t_grid(valid_l); flipud(t_grid(valid_l))], ...
                  [lower_l(valid_l); flipud(upper_l(valid_l))], ...
                  [0.85 0.92 1.00], ...
                  'FaceAlpha', 0.25, 'EdgeColor', 'none', 'DisplayName', 'Shallow threshold band');
            plot(t_grid(valid_l), lower_l(valid_l), 'm--', 'LineWidth', 1.6, 'DisplayName', 'Lower threshold');
            plot(t_grid(valid_l), upper_l(valid_l), 'c--', 'LineWidth', 1.6, 'DisplayName', 'Upper threshold');
        end

        if ~isempty(breaths_lungs.peak_t) && any(isfinite(breaths_lungs.peak_t))
            scatter(breaths_lungs.peak_t, breaths_lungs.amp, 'k.', 'DisplayName', 'Amp')
            y_top_l = max([ ...
                mean(breaths_lungs.amp, 'omitnan') + 3*std(breaths_lungs.amp, 'omitnan'), ...
                max(upper_l(valid_l), [], 'omitnan')], [], 'omitnan');
            if isfinite(y_top_l) && y_top_l > 0
                ylim([0, 1.05 * y_top_l])
            end
            shade_events_on_axis(shallow_events_lungs);
            legend('Location','eastoutside')
        end
        title('Lungs Breath Amplitudes')
        xlabel('Time (s)')
        ylabel('Amplitude')
        grid on
        hold off
    
        % ----------------------
        % Subplot 2: Diaphragm
        % ----------------------
        subplot(3,1,2)
        hold on
        lower_d = ratio_low  * ref_diaph;
        upper_d = ratio_high * ref_diaph;
        valid_d = isfinite(t_grid) & isfinite(lower_d) & isfinite(upper_d) & upper_d >= lower_d;
        if any(valid_d)
            patch([t_grid(valid_d); flipud(t_grid(valid_d))], ...
                  [lower_d(valid_d); flipud(upper_d(valid_d))], ...
                  [0.85 0.92 1.00], ...
                  'FaceAlpha', 0.25, 'EdgeColor', 'none', 'DisplayName', 'Shallow threshold band');
            plot(t_grid(valid_d), lower_d(valid_d), 'm--', 'LineWidth', 1.6, 'DisplayName', 'Lower threshold');
            plot(t_grid(valid_d), upper_d(valid_d), 'c--', 'LineWidth', 1.6, 'DisplayName', 'Upper threshold');
        end
        scatter(breaths_diaph.peak_t, breaths_diaph.amp, 'k.', 'DisplayName', 'Amp')
        y_top_d = max([ ...
            mean(breaths_diaph.amp, 'omitnan') + 3*std(breaths_diaph.amp, 'omitnan'), ...
            max(upper_d(valid_d), [], 'omitnan')], [], 'omitnan');
        if isfinite(y_top_d) && y_top_d > 0
            ylim([0, 1.05 * y_top_d])
        end

        if isempty(shallow_events_diaph)
            legend('Location','eastoutside')
        else
            shade_events_on_axis(shallow_events_diaph);
            legend('Location','eastoutside')
        end
        title('Diaphragm Breath Amplitudes')
        xlabel('Time (s)')
        ylabel('Amplitude')
        grid on
        hold off

        % ----------------------
        % Subplot 3: SpO2 + no_desat mask
        % ----------------------
        subplot(3,1,3)
        hold on
    
        % SpO2 time series (sampled signal)
        spo2 = spo2_feat.spo2(:);
        t_spo2 = spo2_feat.t_spo2(:);
    
        plot(t_spo2, spo2, 'k')
        yline(90, 'r--')
        ylim([89 100])
        xlim([0 1800])
    
        % baseline - drop threshold (informational)
        drop_thr = config.spo2.drop_thr;
        if isfield(baseline,'SpO2_median') && isfinite(baseline.SpO2_median)
            yline(baseline.SpO2_median - drop_thr, 'g--')
        end
    
        % Optional: show desaturation event spans as shaded regions
        if isfield(spo2_feat,'desat_events') && ~isempty(spo2_feat.desat_events)
            shade_events_on_axis(spo2_feat.desat_events);
            legend('SpO₂','90%','Baseline-drop','desat events', 'Location','eastoutside')
        else
            legend('SpO₂','90%','Baseline-drop', 'Location','eastoutside')
        end
    
        title('SpO₂')
        xlabel('Time (s)')
        ylabel('SpO₂ (%)')
        grid on
        hold off
        
        sgtitle(['SHALLOW BREATHING | Subject: ' num2str(config.subject) ...
            ' | Measurement: ' num2str(config.measure) ...
            ' | ' ref_txt ...
            ' | shallow band=' num2str(100*(1-ratio_high)) '-' num2str(100*(1-ratio_low)) '% reduction'])
        
        ax = findall(gcf,'Type','axes');
        
        % exclude legend axes if present
        ax = ax(arrayfun(@(a) ~strcmp(a.Tag,'legend'), ax));
        
        % order top-to-bottom
        ax = flipud(ax);
        
        % horizontal alignment values
        left  = max(arrayfun(@(a) a.Position(1), ax));
        width = min(arrayfun(@(a) a.Position(3), ax));
        
        top_margin = 0.02;
        
        for k = 1:numel(ax)
            p = ax(k).Position;
        
            % align widths
            p(1) = left;
            p(3) = width;
        
            % only move/shrink the top subplot
            if k == 1
                p(2) = p(2) - top_margin;
                p(4) = p(4) - top_margin;
            end
        
            ax(k).Position = p;
        end
        
        linkaxes(ax,'x');
        xlim(ax(1), [0 t_grid(end)]);
        save_figure(config, 'shallow_breathing');
    end    
end

