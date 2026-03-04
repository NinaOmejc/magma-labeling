function [fig, ax, ph] = plot_raw_data(data, config)
% plotPhysSignals  Plot 6 physiological signals (columns)
%
% Usage:
%   [fig, ax, ph] = plotPhysSignals(data, fs)
%   [fig, ax, ph] = plotPhysSignals(data, fs, [5 10])
%
% Outputs:
%   fig - figure handle
%   ax  - axes handles (6x1)
%   ph  - plot (line) handles (6x1)

    if ~config.plot_raw_data
        fig = [];
        ax  = [];
        ph  = [];
        return;
    end

    % Time vector
    N = size(data,1);
    t = (0:N-1) / config.fs;

    fig = figure('Units','pixels','Position',[100 100 1200 800], 'Visible', config.make_figs_visible); 
    tl = tiledlayout(6,1);

    ax = gobjects(6,1);
    ph = gobjects(6,1);

    for k = 1:6
        ax(k) = nexttile;
        ph(k) = plot(t, data(:,k));
        ylabel(config.data_columns{k})

        if ~isempty(config.plot_raw_data_xrange)
            xlim(ax(k), config.plot_raw_data_xrange)
        end

        if k == 1
            title(['Subject: ' num2str(config.subject) ' | Condition: ' num2str(config.condition) ' | Physiological Signals'])
        end

        if k == 6
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