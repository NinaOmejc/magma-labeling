function save_figure(config, base_name)
% save_current_figure
% If config.save_plots == true:
%   - saves current figure as PNG
%   - closes the figure
% If false:
%   - does nothing (figure remains open)

    if ~isfield(config,'save_plots') || ~config.save_plots
        return;   % leave figure open
    end

    if ~isfield(config,'sub_results_path') || isempty(config.sub_results_path)
        warning('No results_path defined. Plot not saved.');
        return;
    end

    % Ensure folder exists
    if ~isfolder(config.sub_results_path)
        mkdir(config.sub_results_path);
    end

    % Resize figure BEFORE saving
    fig = gcf;
    if isfield(config,'fig_width') && isfield(config,'fig_height')
        set(fig, 'Units', 'pixels');
        fig.Position(3) = config.fig_width;
        fig.Position(4) = config.fig_height;
    end

    % Optional: ensure white background
    set(fig, 'Color', 'w');

    % Reduce font sizes globally
    fontsize = 10;
    allAxes = findall(fig, 'Type', 'axes');
    set(allAxes, 'FontSize', fontsize);   % change 9 to what you want
    
    allText = findall(fig, 'Type', 'text');
    set(allText, 'FontSize', fontsize);
    
    allLeg = findall(fig, 'Type', 'legend');
    set(allLeg, 'FontSize', fontsize);

    % Build filename
    fname = sprintf('Sub%d_Cond%d_%s.png', ...
        config.subject, ...
        config.condition, ...
        base_name);

    fullpath = fullfile(config.sub_results_path, fname);

    % Save with high quality
    
    if (contains(base_name, 'lungs') && ~contains(base_name, 'baseline')) || ...
       (contains(base_name, 'diaph') && ~contains(base_name, 'baseline'))
        set(fig, 'Visible', 'on')
        savefig(fig, replace(fullpath, '.png', '.fig'))
    else
        exportgraphics(fig, fullpath, 'Resolution', config.plot_dpi);
    end

    % Close figure after saving
    close(fig);
end