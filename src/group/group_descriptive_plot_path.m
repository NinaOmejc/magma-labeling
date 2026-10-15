function path = group_descriptive_plot_path(config, out_dir, stem)
% GROUP_DESCRIPTIVE_PLOT_PATH Use the existing plot-format convention.
    fmt = 'png';
    if isfield(config, 'plot_format') && ~isempty(config.plot_format)
        fmt = lower(char(string(config.plot_format)));
    end
    if ~ismember(fmt, {'png','jpg','jpeg','tif','tiff','pdf','eps','fig'})
        fmt = 'png';
    end
    path = fullfile(out_dir, [stem '.' fmt]);
end

