function [fig, ax, ph] = plot_raw_data(data, config)
% PLOT_RAW_DATA Plot every physiological channel on the native sample timeline.
%
% Inputs:
%   data   - Nsample x Nchannel signal matrix aligned with config.times.
%   config - Pipeline settings with channel names, visibility, and x-range options.
%
% Outputs:
%   fig - Figure handle.
%   ax - Axes handle or array.
%   ph - Nchannel x 1 line-handle array; all outputs are empty when disabled.

    if ~config.plot_raw_data
        fig = [];
        ax  = [];
        ph  = [];
        return;
    end

    n_cols = size(data, 2);
    fig = figure('Units','pixels','Position', near_fullscreen_figure_position(), 'Visible', config.make_figs_visible); 
    tiledlayout(n_cols, 1);

    ax = gobjects(n_cols, 1);
    ph = gobjects(n_cols, 1);

    for k = 1:n_cols
        ax(k) = nexttile;
        ph(k) = plot(config.times, data(:,k));
        ylabel(config.data_columns{k})

        if ~isempty(config.plot_raw_data_xrange)
            xlim(ax(k), config.plot_raw_data_xrange)
        end

        if k == 1
            title(['Subject: ' num2str(config.subject) ' | Measurement: ' num2str(config.measure) ' | Physiological Signals'])
        end

        if k == n_cols
            xlabel('Time (s)')
        end
    end
    
    % fix interaction warning
    for k = 1:numel(ax)
        if isprop(ax(k),'Toolbar') && ~isempty(ax(k).Toolbar)
            ax(k).Toolbar.Visible = 'off';
        end
    end
    save_figure(config, 'raw_data');
end
