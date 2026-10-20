function fig = plot_thoracic_rhythmicity_diagnostic(data, qc, diagnostic, config)
% PLOT_THORACIC_RHYTHMICITY_DIAGNOSTIC Compare belts without amplitude calibration.
% diagnostic is the optional, unsaved output of the existing Q23 calculation.
% The abdominal concentration is supplementary plotting evidence only.
    fig = [];
    if ~get_config_value(config,'PhenotypeSummary','do_plot',true), return; end
    blue = [0 0.447 0.741]; orange = [0.85 0.325 0.098];
    fig = figure('Visible',config.make_figs_visible,'Color','w', ...
        'Units','pixels','Position',near_fullscreen_figure_position());
    cleanup = onCleanup(@() delete_if_open(fig)); %#ok<NASGU>
    layout = tiledlayout(fig,6,1,'TileSpacing','compact','Padding','loose');
    title(layout,sprintf('RESPIRATORY OSCILLATIONS AND SPECTRAL CONCENTRATION | Sub%d M%d', ...
        config.subject,config.measure));
    channels = resolve_signal_channels(config);
    fs = config.fs; N = size(data,1); p = qc.parameters;
    n = round(p.window_sec*fs);
    representative = ~isempty(diagnostic.representative_window);
    if representative
        first = diagnostic.window_start_idx(diagnostic.representative_window);
        window_title = sprintf('1. Oscillations | Representative valid %.0f s window',p.window_sec);
    else
        first = fallback_start(data,channels.channels,n);
        window_title = {'1. Available signal evidence only (unscored)', ...
            ['No valid Q23 window: ' strrep(qc.missing_reason,'_',' ')]};
    end
    idx = first:min(N,first+n-1);
    t = (idx-1)/fs;
    thoracic = nexttile(layout,1);
    plot_trace(thoracic,data,idx,t,channels.channels.lungs_idx,blue, ...
        'Thoracic',is_lung_belt_ignored(config));
    title(thoracic,window_title,'Interpreter','none');
    abdominal = nexttile(layout,2);
    plot_trace(abdominal,data,idx,t,channels.channels.diaph_idx,orange,'Abdominal',false);
    xlabel(abdominal,{'Recording time (s)', ...
        'Original units; absolute amplitudes are not calibrated between belts'});
    linkaxes([thoracic abdominal],'x');
    if ~isempty(t), xlim(thoracic,[t(1) (idx(end))/fs]); end

    spectra = nexttile(layout,3,[2 1]);
    spectra.Tag = 'RhythmicitySpectra';
    hold(spectra,'on'); grid(spectra,'on');
    title(spectra,{'2. Welch spectral-shape comparison', ...
        'Each PSD / its own band power; normalization removes absolute power information'});
    xlabel(spectra,'Frequency (Hz)'); ylabel(spectra,'Normalized PSD (Hz^{-1})');
    xlim(spectra,p.power_band_hz);
    if representative
        detail = diagnostic.representative;
        f = detail.frequency_hz;
        query = [p.power_band_hz(1); f(f>p.power_band_hz(1) & f<p.power_band_hz(2)); p.power_band_hz(2)];
        th_psd = interp1(f,detail.thoracic_normalized_psd,query,'linear');
        ab_psd = nan(size(query));
        if ~isempty(detail.abdominal_normalized_psd)
            ab_psd = interp1(f,detail.abdominal_normalized_psd,query,'linear');
        end
        ymax = 1.1*max([th_psd;ab_psd],[],'omitnan');
        ylim(spectra,[0 ymax]);
        band = detail.integration_band_hz;
        patch(spectra,[band(1) band(2) band(2) band(1)],[0 0 ymax ymax], ...
            [0.7 0.7 0.7],'FaceAlpha',0.25,'EdgeColor','none', ...
            'DisplayName','Q23 integration band','Tag','Q23IntegrationBand');
        plot(spectra,query,th_psd,'Color',blue,'LineWidth',1.4, ...
            'DisplayName','Thoracic','Tag','ThoracicNormalizedPSD');
        if any(isfinite(ab_psd))
            plot(spectra,query,ab_psd,'Color',orange,'LineWidth',1.4, ...
                'DisplayName','Abdominal','Tag','AbdominalNormalizedPSD');
        else
            text(spectra,0.98,0.9,['Abdominal PSD unavailable: ' ...
                strrep(detail.abdominal_missing_reason,'_',' ')], ...
                'Units','normalized','HorizontalAlignment','right','Interpreter','none');
        end
        xline(spectra,detail.reference_frequency_hz,'k:', ...
            sprintf('f_{AB} = %.3f Hz',detail.reference_frequency_hz), ...
            'DisplayName','Abdominal-derived f_{AB}','Tag','AbdominalReferenceFrequency');
        legend(spectra,'show','Location','northeast');
    else
        text(spectra,0.5,0.5,['No valid Q23 spectrum: ' strrep(qc.missing_reason,'_',' ')], ...
            'Units','normalized','HorizontalAlignment','center','Interpreter','none');
    end

    summary = nexttile(layout,5,[2 1]);
    summary.Tag = 'RhythmicitySummary';
    hold(summary,'on'); grid(summary,'on');
    centers = (diagnostic.window_start_idx-1)/fs + p.window_sec/2;
    th_valid = isfinite(diagnostic.thoracic_values);
    ab_valid = th_valid & isfinite(diagnostic.abdominal_values);
    th_median = qc.thoracic_respiratory_rhythmicity;
    ab_median = NaN;
    if any(ab_valid), ab_median = median(diagnostic.abdominal_values(ab_valid)); end
    plot(summary,centers(th_valid),diagnostic.thoracic_values(th_valid),'o', ...
        'Color',blue,'MarkerFaceColor',blue,'DisplayName','Thoracic Q23 windows', ...
        'Tag','ThoracicWindowConcentration');
    plot(summary,centers(ab_valid),diagnostic.abdominal_values(ab_valid),'s', ...
        'Color',orange,'MarkerSize',8,'DisplayName','Abdominal windows (supplementary)', ...
        'Tag','AbdominalWindowConcentration');
    if isfinite(th_median)
        yline(summary,th_median,'-','Color',blue,'DisplayName','Thoracic median', ...
            'Tag','ThoracicMedian');
    end
    if isfinite(ab_median)
        yline(summary,ab_median,'--','Color',orange,'DisplayName','Abdominal median', ...
            'Tag','AbdominalMedian');
    end
    ylim(summary,[0 1]); ylabel(summary,'Spectral concentration (0-1)');
    if ~isempty(centers), xlim(summary,[0 max(N/fs,1)]); end
    ab_coverage = window_coverage(diagnostic.window_start_idx(ab_valid),n,N);
    title(summary,{sprintf('3. Q23 median: %s | Abdominal median: %s (supplementary)', ...
        score_text(th_median),score_text(ab_median)), ...
        sprintf('Thoracic: %d/%d valid windows, %.1f%% coverage | Abdominal: %d/%d, %.1f%% coverage', ...
        qc.n_valid_windows,qc.n_windows,100*qc.valid_coverage_fraction, ...
        nnz(ab_valid),qc.n_windows,100*ab_coverage)},'Interpreter','none');
    status = get_config_value(config,'recording_observations','status','not_assessed');
    xlabel(summary,{'Window center (s)', ...
        ['Clinician thoracic-excursion observation (independent): ' strrep(status,'_',' ')], ...
        'Spectral concentration is not an excursion-severity score; no classification cutoff'});
    if any(th_valid) || any(ab_valid)
        legend(summary,'show','Location','best');
    else
        text(summary,0.5,0.5,'No valid window concentrations', ...
            'Units','normalized','HorizontalAlignment','center');
    end
    save_figure(config,'thoracic_rhythmicity_diagnostic');
end

function plot_trace(ax,data,idx,t,channel,color,name,ignored)
    ax.Tag = [name 'Oscillations'];
    if ~ignored && ~isempty(channel) && channel <= size(data,2) && ~isempty(idx) && ...
            any(isfinite(data(idx,channel)))
        plot(ax,t,data(idx,channel),'Color',color,'Tag',[name 'PreprocessedSignal']);
    else
        text(ax,0.5,0.5,[name ' signal unavailable'],'Units','normalized', ...
            'HorizontalAlignment','center');
    end
    ylabel(ax,name); grid(ax,'on');
end

function first = fallback_start(data,channels,n)
    first = 1;
    columns = [channels.lungs_idx channels.diaph_idx];
    columns = columns(columns<=size(data,2));
    if isempty(columns), return; end
    available = find(any(isfinite(data(:,columns)),2),1);
    if ~isempty(available), first = max(1,min(available,size(data,1)-n+1)); end
end

function fraction = window_coverage(starts,n,N)
    covered = false(N,1);
    for first = starts(:)', covered(first:min(N,first+n-1)) = true; end
    fraction = nnz(covered)/max(1,N);
end

function label = score_text(value)
    if isfinite(value), label = sprintf('%.3f',value);
    else, label = 'Unavailable'; end
end

function delete_if_open(fig)
    if isgraphics(fig), delete(fig); end
end
