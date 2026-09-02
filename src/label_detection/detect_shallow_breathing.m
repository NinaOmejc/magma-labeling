function shallow_events = detect_shallow_breathing(data, phys_feat, baseline, spo2_feat, config)
% detect_shallow_breathing
% Event-based detection of shallow breathing episodes (Label 1).
%
% Criteria (Labels.docx):
%   - Clear reduction in amplitude of respiratory belts (lungs + diaphragm),
%     without complete disappearance, with preserved or increased RR.
%   - Amplitude reduction: 20–35% of reference amplitude (60 s analysis windows).
%   - Duration: sustained >= 30 s.
%   - No desaturation: SpO2 < 90 OR SpO2 drop >= 3–4% below baseline (baseline from first 30–60 s).
% Detector grids map to master samples using config.fs.

    disp('Starting label detection ...')

    % ---- indices ---
    N = size(data,1);
    t_grid = phys_feat.resp.time_sec;
    lungs = phys_feat.resp.lungs;
    diaph = phys_feat.resp.diaph;
    lungs_valid = lungs.session_amplitude_available;
    diaph_valid = diaph.session_amplitude_available;

    if ~lungs_valid && ~diaph_valid
        fprintf('Skipping shallowB detection: no valid respiratory belt with usable breath amplitudes.\n');
        shallow_events = empty_events();
        return;
    end

    % ---- shallow condition on grid, using one fixed session reference ----
    shallow_mask_lungs = false(size(t_grid));
    if lungs_valid
        shallow_mask_lungs = lungs.shallow_amplitude_mask;
    end

    shallow_mask_diaph = false(size(t_grid));
    if diaph_valid
        shallow_mask_diaph = diaph.shallow_amplitude_mask;
    end

    % ---- no-desaturation condition on grid ----
    desat_mask = false(size(t_grid));
    if isfield(phys_feat, 'spo2') && isfield(phys_feat.spo2, 'desaturation_events')
        desat_mask = get_desaturation_mask(phys_feat.spo2.desaturation_events, t_grid);
    end

    exclude_desat = true;
    if isfield(config, 'ShB') && isfield(config.ShB, 'exclude_desat')
        exclude_desat = config.ShB.exclude_desat;
    end
    no_desat = ~desat_mask | ~exclude_desat;

    % final condition (grid)
    shallow_mask_lungs_final = shallow_mask_lungs & no_desat;
    shallow_mask_diaph_final = shallow_mask_diaph & no_desat;
    
    % convert sustained grid runs -> events (>=30 s)
    [shallow_events_lungs, ~] = sustained_condition_to_events( ...
        shallow_mask_lungs_final, t_grid, config.fs, N, config.ShB.min_dur_sec, 'shallow_breathing_lungs');
    [shallow_events_diaph, ~] = sustained_condition_to_events( ...
        shallow_mask_diaph_final, t_grid, config.fs, N, config.ShB.min_dur_sec, 'shallow_breathing_diaph');
    
    shallow_events = merge_events({shallow_events_lungs, shallow_events_diaph});
    % shallow_mask = events_to_sample_mask(events, N, config.fs);
    
    % add a figure
    if config.ShB.do_plot

        ratio_low  = config.ShB.amp_ratio_low;
        ratio_high = config.ShB.amp_ratio_high;
        ref_txt = 'Fixed per-belt protocol/session amplitude reference';
        ref_lungs_grid = lungs.session_reference_value * ones(size(t_grid));
        ref_diaph_grid = diaph.session_reference_value * ones(size(t_grid));
        
        fig = figure('Units','pixels','Position', near_fullscreen_figure_position(), 'Visible', config.make_figs_visible); 
        % ----------------------
        % Subplot 1: Lungs
        % ----------------------
        subplot(3,1,1)
        hold on
        lower_l = ratio_low  * ref_lungs_grid;
        upper_l = ratio_high * ref_lungs_grid;
        valid_l = isfinite(t_grid) & isfinite(lower_l) & isfinite(upper_l) & upper_l >= lower_l;
        if any(valid_l)
            patch([t_grid(valid_l); flipud(t_grid(valid_l))], ...
                  [lower_l(valid_l); flipud(upper_l(valid_l))], ...
                  [0.85 0.92 1.00], ...
                  'FaceAlpha', 0.25, 'EdgeColor', 'none', 'DisplayName', 'Shallow threshold band');
            plot(t_grid(valid_l), lower_l(valid_l), 'm--', 'LineWidth', 1.6, 'DisplayName', 'Lower threshold');
            plot(t_grid(valid_l), upper_l(valid_l), 'c--', 'LineWidth', 1.6, 'DisplayName', 'Upper threshold');
        end

        if ~isempty(lungs.peak_t) && any(isfinite(lungs.peak_t))
            scatter(lungs.peak_t, lungs.amp, 'k.', 'DisplayName', 'Amp')
            y_top_l = max([ ...
                mean(lungs.amp, 'omitnan') + 3*std(lungs.amp, 'omitnan'), ...
                max(upper_l(valid_l), [], 'omitnan')], [], 'omitnan');
            if isfinite(y_top_l) && y_top_l > 0
                ylim([0, 1.05 * y_top_l])
            end
            shade_events_on_axis(gca, shallow_events_lungs);
            legend('Location','eastoutside')
        end
        title('Lungs Breath Amplitudes')
        xlabel('Time (s)')
        ylabel('Belt excursion (raw units)')
        grid on
        hold off
    
        % ----------------------
        % Subplot 2: Diaphragm
        % ----------------------
        subplot(3,1,2)
        hold on
        lower_d = ratio_low  * ref_diaph_grid;
        upper_d = ratio_high * ref_diaph_grid;
        valid_d = isfinite(t_grid) & isfinite(lower_d) & isfinite(upper_d) & upper_d >= lower_d;
        if any(valid_d)
            patch([t_grid(valid_d); flipud(t_grid(valid_d))], ...
                  [lower_d(valid_d); flipud(upper_d(valid_d))], ...
                  [0.85 0.92 1.00], ...
                  'FaceAlpha', 0.25, 'EdgeColor', 'none', 'DisplayName', 'Shallow threshold band');
            plot(t_grid(valid_d), lower_d(valid_d), 'm--', 'LineWidth', 1.6, 'DisplayName', 'Lower threshold');
            plot(t_grid(valid_d), upper_d(valid_d), 'c--', 'LineWidth', 1.6, 'DisplayName', 'Upper threshold');
        end
        scatter(diaph.peak_t, diaph.amp, 'k.', 'DisplayName', 'Amp')
        y_top_d = max([ ...
            mean(diaph.amp, 'omitnan') + 3*std(diaph.amp, 'omitnan'), ...
            max(upper_d(valid_d), [], 'omitnan')], [], 'omitnan');
        if isfinite(y_top_d) && y_top_d > 0
            ylim([0, 1.05 * y_top_d])
        end

        if isempty(shallow_events_diaph)
            legend('Location','eastoutside')
        else
            shade_events_on_axis(gca, shallow_events_diaph);
            legend('Location','eastoutside')
        end
        title('Diaphragm Breath Amplitudes')
        xlabel('Time (s)')
        ylabel('Belt excursion (raw units)')
        grid on
        hold off

        % ----------------------
        % Subplot 3: SpO2 + desaturation thresholds
        % ----------------------
        ax_spo2 = subplot(3,1,3);
        plot_spo2_diagnostic_panel(ax_spo2, data, baseline, spo2_feat, config, 'SpO2 with desaturation thresholds');
        
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

        set(fig, 'Visible', config.make_figs_visible);
        
        linkaxes(ax,'x');
        xlim(ax(1), [0 t_grid(end)]);
        save_figure(config, 'shallow_breathing');
    end    
end
