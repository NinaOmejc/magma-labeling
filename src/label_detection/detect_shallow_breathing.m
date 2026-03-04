function events = detect_shallow_breathing(data, baseline, b_l, b_d, spo2_feats, config)
% detect_shallow_breathing
% Event-based detection of shallow breathing episodes (Label 1).
%
% Criteria (Labels.docx):
%   - Clear reduction in amplitude of respiratory belts (lungs + diaphragm),
%     without complete disappearance, with preserved or increased RR.
%   - Amplitude reduction: 20–35% of reference amplitude (60 s analysis windows).
%   - Duration: sustained >= 30 s.
%   - No desaturation: SpO2 < 90 OR SpO2 drop >= 3–4% below baseline (baseline from first 30–60 s).
%
% This implementation is "timepoint-based" (evaluated on a time grid), then
% converted to continuous events and filtered by duration >= 30 s.
% Internally it uses a rolling 60 s reference window to estimate breath amplitude,
% consistent with the "60 s analysis windows" requirement, but the output is
% event intervals with arbitrary length.
%
% Usage:
%   events = detect_shallow_breathing(data, fs, columns, baseline)
%   events = detect_shallow_breathing(data, fs, columns, baseline, params)
%
% Required baseline fields:
%   baseline.lungs_amp_ref
%   baseline.diap_amp_ref
%   baseline.spo2_median (or baseline.spo2_mean; see params)
%
% Output:
%   events struct array with fields:
%     type, start_idx, end_idx, start_t, end_t

    % ---- indices ---
    N = size(data,1);
    t_grid = (0:config.grid_step_sec:(N-1)/config.fs)';  % seconds

    % ---- shallow condition on grid (amp ratio in [0.2,0.35] for BOTH) ----
    shallow_amp = shallow_amp_condition_on_grid( ...
        b_l, b_d, t_grid, config.ShB.analysis_win_sec, ...
        baseline.lungs_amp_ref, baseline.diap_amp_ref, ...
        config.ShB.amp_ratio_low, config.ShB.amp_ratio_high);

    % ---- no-desaturation condition on grid ----
    no_desat = no_desat_from_events_on_grid(spo2_feats.desat_events, t_grid);

    % final condition (grid)
    cond_grid = shallow_amp & no_desat;
    
    % convert grid runs -> events (>=30 s)
    ev_grid = runs_to_events(cond_grid, 1/config.grid_step_sec, config.ShB.min_dur_sec, 'shallow_breathing');
    events = grid_events_to_sample_events(ev_grid, config.fs, N);
    % shallow_mask = events_to_sample_mask(events, N, config.fs);
    
    % add a figure
    if config.ShB.do_plot

        lungs_ref = baseline.lungs_amp_ref;
        diag_ref  = baseline.diap_amp_ref;
        ratio_low  = config.ShB.amp_ratio_low;
        ratio_high = config.ShB.amp_ratio_high;
        % Reference bounds
        lungs_lower = ratio_low  * lungs_ref;
        lungs_upper = ratio_high * lungs_ref;
        diag_lower  = ratio_low  * diag_ref;
        diag_upper  = ratio_high * diag_ref;
        
        figure('Units','pixels','Position',[100 100 1200 800], 'Visible', config.make_figs_visible); 
        % ----------------------
        % Subplot 1: Lungs
        % ----------------------
        subplot(3,1,1)
        hold on
        plot(b_l.peak_t, b_l.amp, 'k')
        yline(lungs_ref, '--', 'Baseline')
        yline(lungs_lower, 'r--', '')
        yline(lungs_upper, 'r--', '')
        ylim([0, mean(b_l.amp, 'omitnan') + 3*std(b_l.amp, 'omitnan')])
        xline(60, 'k--', 'ref');
        shade_events_on_axis(events);
        title('Lungs Breath Amplitudes')
        xlabel('Time (s)')
        ylabel('Amplitude')
        legend('Amp','Baseline','Lower','Upper', 'Location','eastoutside')
        grid on
        hold off
    
        % ----------------------
        % Subplot 2: Diaphragm
        % ----------------------
        subplot(3,1,2)
        hold on
        plot(b_d.peak_t, b_d.amp, 'k')
        yline(diag_ref, '--', 'Baseline')
        yline(diag_lower, 'r--', '')
        yline(diag_upper, 'r--', '')
        xline(60, 'k--', '');
        ylim([0, mean(b_d.amp, 'omitnan') + 3*std(b_d.amp, 'omitnan')])
        shade_events_on_axis(events);
        title('Diaphragm Breath Amplitudes')
        xlabel('Time (s)')
        ylabel('Amplitude')
        legend('Amp','Baseline','Lower','Upper', 'Location','eastoutside')
        grid on
        hold off

        % ----------------------
        % Subplot 3: SpO2 + no_desat mask
        % ----------------------
        subplot(3,1,3)
        hold on
    
        % SpO2 time series (sampled signal)
        spo2 = spo2_feats.spo2(:);
        t_spo2 = spo2_feats.t_spo2(:);
    
        plot(t_spo2, spo2, 'k')
        yline(90, 'r--')
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
        plot(t_grid, y0 + (y1-y0)*double(no_desat), 'b')
    
        % Optional: show desaturation event spans as shaded regions
        if isfield(spo2_feats,'desat_events') && ~isempty(spo2_feats.desat_events)
            shade_events_on_axis(spo2_feats.desat_events);
            legend('SpO₂','90%','Baseline-drop','no desat','desat events', 'Location','eastoutside')
        else
            legend('SpO₂','90%','Baseline-drop','no desat', 'Location','eastoutside')
        end
    
        title('SpO₂ and no\_desat mask (event-based)')
        xlabel('Time (s)')
        ylabel('SpO₂ (%)')
        sgtitle(['SHALLOW BREATHING' newline 'Subject: ' num2str(config.subject) ' | Condition: ' num2str(config.condition)])
        grid on

        ax = findall(gcf,'Type','axes');

        % Keep only real axes (exclude legend axes if any)
        ax = ax(arrayfun(@(a) ~strcmp(a.Tag,'legend'), ax));
        
        % Ensure order top->bottom (optional)
        ax = flipud(ax);
        
        % Use the minimum width among axes and the maximum left margin
        left  = max(arrayfun(@(a) a.Position(1), ax));
        width = min(arrayfun(@(a) a.Position(3), ax));
        
        for k = 1:numel(ax)
            p = ax(k).Position;
            p(1) = left;
            p(3) = width;
            ax(k).Position = p;
        end
        linkaxes(ax,'x');          % tie x-zoom/pan
        xlim(ax(1), [0 t_grid(end)]);     % or whatever common range you want
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
