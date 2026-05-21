function save_figure(config, base_name, save_matfig)
% save_current_figure
% If config.save_plots == true:
%   - saves current figure as PNG
%   - closes the figure
% If false:
%   - does nothing (figure remains open)

    if nargin < 3 || isempty(save_matfig)
        save_matfig = false;
    end

    % Resize figure BEFORE saving
    fig = gcf;
    target_visibility = resolve_target_visibility(config);
    if ~strcmpi(fig.Visible, target_visibility)
        set(fig, 'Visible', target_visibility);
        drawnow;
    end

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

    % Light global readability improvements
    if ~isempty(allAxes)
        set(allAxes, 'Box', 'off', 'LineWidth', 1.0, 'TickDir', 'out');
        for ia = 1:numel(allAxes)
            allAxes(ia).GridAlpha = 0.2;
            allAxes(ia).MinorGridAlpha = 0.1;
        end
    end
    
    allText = findall(fig, 'Type', 'text');
    set(allText, 'FontSize', fontsize);
    
    allLeg = findall(fig, 'Type', 'legend');
    set(allLeg, 'FontSize', fontsize);

    % Make dashed traces easier to see everywhere.
    dashed_width = 1.6;
    if isfield(config, 'plot_dashed_line_width') && ~isempty(config.plot_dashed_line_width)
        dashed_width = config.plot_dashed_line_width;
    end
    strengthen_dashed_lines(fig, dashed_width);
    align_axes_x_widths(allAxes);

    if ~isfield(config,'save_plots') || ~config.save_plots
        if strcmpi(target_visibility, 'off')
            close(fig);
        end
        return;   % leave visible figures open for interactive inspection
    end

    if ~isfield(config,'sub_results_path') || isempty(config.sub_results_path)
        warning('No results_path defined. Plot not saved.');
        return;
    end

    % Ensure folder exists
    if ~isfolder(config.sub_results_path)
        mkdir(config.sub_results_path);
    end

    % Build filename
    fname = sprintf('Sub%d_M%d_%s.png', ...
        config.subject, ...
        config.measure, ...
        base_name);

    fullpath = fullfile(config.sub_results_path, fname);

    % Save with high quality
    
    if (contains(base_name, 'lungs') && ~contains(base_name, 'baseline') && ~contains(base_name, 'normality')) || ...
       (contains(base_name, 'diaph') && ~contains(base_name, 'baseline') && ~contains(base_name, 'normality')) || ...
       save_matfig
        save_fig_for_direct_open(fig, replace(fullpath, '.png', '.fig'));
    else
        if ~strcmpi(fig.Visible, target_visibility)
            set(fig, 'Visible', target_visibility);
            drawnow;
        end
        exportgraphics(fig, fullpath, 'Resolution', config.plot_dpi);
    end

    % Close figure after saving
    close(fig);
end

function save_fig_for_direct_open(fig, fig_path)
% Save a .fig created invisibly so double-clicking opens it visibly later,
% without making the live batch figure visible during saving.

    original_create_fcn = fig.CreateFcn;
    cleanup = onCleanup(@() set(fig, 'CreateFcn', original_create_fcn));
    fig.CreateFcn = @(src, event) set(src, 'Visible', 'on');
    savefig(fig, fig_path);
end

function strengthen_dashed_lines(fig, target_width)
    if nargin < 2 || isempty(target_width) || ~isfinite(target_width) || target_width <= 0
        target_width = 1.6;
    end

    candidates = findall(fig, '-property', 'LineStyle');
    for i = 1:numel(candidates)
        h = candidates(i);
        try
            ls = get(h, 'LineStyle');
            if ischar(ls) || isstring(ls)
                ls = char(ls);
                if strcmp(ls, '--') || strcmp(ls, '-.')
                    if isprop(h, 'LineWidth')
                        lw = get(h, 'LineWidth');
                        if isempty(lw) || ~isfinite(lw) || lw < target_width
                            set(h, 'LineWidth', target_width);
                        end
                    end
                end
            end
        catch
            % Ignore handles that do not expose standard line style/width access.
        end
    end
end

function visibility = resolve_target_visibility(config)
    visibility = 'on';
    if isfield(config, 'make_figs_visible') && ~isempty(config.make_figs_visible)
        visibility = char(string(config.make_figs_visible));
    end
end
