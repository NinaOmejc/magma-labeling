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

    % ---- shallow condition on grid  ----
    ref_lungs = get_resp_ref_on_grid(baseline, 'lungs', t_grid);
    ref_diap = get_resp_ref_on_grid(baseline, 'diap', t_grid);

    shallow_mask_lungs = compute_shallow_breathing_mask( ...
        breaths_lungs, t_grid, config.ShB.min_dur_sec, ...
        ref_lungs, config.ShB.amp_ratio_low, config.ShB.amp_ratio_high);

    shallow_mask_diaph = compute_shallow_breathing_mask( ...
        breaths_diaph, t_grid, config.ShB.min_dur_sec, ...
        ref_diap, config.ShB.amp_ratio_low, config.ShB.amp_ratio_high);

    % ---- no-desaturation condition on grid ----
    no_desat = no_desat_from_events_on_grid(spo2_feat.desat_events, t_grid);

    % final condition (grid)
    shallow_mask_lungs_final = shallow_mask_lungs & no_desat;
    shallow_mask_diaph_final = shallow_mask_diaph & no_desat;
    
    % convert grid runs -> events (>=30 s)
    shallow_ev_grid_lungs = runs_to_events(shallow_mask_lungs_final, 1/config.grid_step_sec, config.ShB.min_dur_sec, 'shallow_breathing_lungs');
    shallow_events_lungs = grid_events_to_sample_events(shallow_ev_grid_lungs, config.fs, N);

    shallow_ev_grid_diaph = runs_to_events(shallow_mask_diaph_final, 1/config.grid_step_sec, config.ShB.min_dur_sec, 'shallow_breathing_diaph');
    shallow_events_diaph = grid_events_to_sample_events(shallow_ev_grid_diaph, config.fs, N);
    
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
        
        figure('Units','pixels','Position',[100 100 1200 800], 'Visible', config.make_figs_visible); 
        % ----------------------
        % Subplot 1: Lungs
        % ----------------------
        subplot(3,1,1)
        hold on
        scatter(breaths_lungs.peak_t, breaths_lungs.amp, 'k.')
        if ~isnan(breaths_lungs.peak_t)
            ylim([0, mean(breaths_lungs.amp, 'omitnan') + 3*std(breaths_lungs.amp, 'omitnan')])
            shade_events_on_axis(shallow_events_lungs);
            legend('Amp','Detected events', 'Location','eastoutside')
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
        scatter(breaths_diaph.peak_t, breaths_diaph.amp, 'k.')
        ylim([0, mean(breaths_diaph.amp, 'omitnan') + 3*std(breaths_diaph.amp, 'omitnan')])
        shade_events_on_axis(shallow_events_diaph);
        title('Diaphragm Breath Amplitudes')
        xlabel('Time (s)')
        ylabel('Amplitude')
        legend('Amp','Detected events', 'Location','eastoutside')
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
    
        % Plot no_desat as a binary trace near bottom (scaled)
        spo2_min = min(spo2, [], 'omitnan');
        spo2_max = max(spo2, [], 'omitnan');
        y0 = spo2_min + 0.05*(spo2_max - spo2_min);
        y1 = spo2_min + 0.20*(spo2_max - spo2_min);
        % plot(t_grid, y0 + (y1-y0)*double(no_desat), 'b')
    
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

% ===================== helper functions =====================

function no_desat = no_desat_from_events_on_grid(desat_events, t_grid)
% no_desat(t)=true if t is NOT inside any desaturation event
    no_desat = true(size(t_grid));
    for k = 1:numel(desat_events)
        in_event = (t_grid >= desat_events(k).start_t) & (t_grid <= desat_events(k).end_t);
        no_desat(in_event) = false;
    end
end
