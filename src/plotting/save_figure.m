function save_figure(config, base_name, save_matfig, output_path)
% save_current_figure
% Save current figure to the subject output folder and close it.

    if nargin < 3 || isempty(save_matfig)
        save_matfig = false;
    end
    if nargin < 4
        output_path = '';
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

    plot_format = resolve_plot_format(config);
    if ~isempty(output_path)
        fullpath = char(string(output_path));
    else
        if ~isfield(config,'sub_results_path') || isempty(config.sub_results_path)
            warning('No results_path defined. Plot not saved.');
            return;
        end

        fname = sprintf('Sub%d_M%d_%s.%s', ...
            config.subject, ...
            config.measure, ...
            base_name, ...
            plot_format);
        fullpath = fullfile(config.sub_results_path, fname);
    end

    out_dir = fileparts(fullpath);
    if ~isempty(out_dir) && ~isfolder(out_dir)
        mkdir(out_dir);
    end

    [full_dir, full_stem, ~] = fileparts(fullpath);
    fig_sidecar_path = fullfile(full_dir, [full_stem '.fig']);

    % Save with high quality

    save_fig_sidecar = (contains(base_name, 'lungs') && ~contains(base_name, 'normality')) || ...
                       (contains(base_name, 'diaph') && ~contains(base_name, 'normality')) || ...
                       save_matfig;
    if save_fig_sidecar
        save_fig_for_direct_open(fig, fig_sidecar_path);
    end

    if strcmpi(plot_format, 'fig')
        save_fig_for_direct_open(fig, fullpath);
    else
        if ~strcmpi(fig.Visible, target_visibility)
            set(fig, 'Visible', target_visibility);
            drawnow;
        end
        dpi = resolve_plot_dpi(config);
        exportgraphics(fig, fullpath, 'Resolution', dpi);
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

function plot_format = resolve_plot_format(config)
    plot_format = 'png';
    if isfield(config, 'plot_format') && ~isempty(config.plot_format)
        plot_format = lower(strtrim(char(string(config.plot_format))));
    end

    valid_formats = {'png', 'jpg', 'jpeg', 'tif', 'tiff', 'pdf', 'eps', 'fig'};
    if ~ismember(plot_format, valid_formats)
        warning('Unsupported plot format "%s". Falling back to png.', plot_format);
        plot_format = 'png';
    end
end

function dpi = resolve_plot_dpi(config)
    dpi = 150;
    if isfield(config, 'plot_dpi') && ~isempty(config.plot_dpi) && isfinite(config.plot_dpi) && config.plot_dpi > 0
        dpi = config.plot_dpi;
    end
end
