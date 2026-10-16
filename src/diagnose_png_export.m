function report = diagnose_png_export(config, subject, measure, failed_figure)
% DIAGNOSE_PNG_EXPORT Data-free, standalone PNG/path diagnostic for MAGMA.
% report = diagnose_png_export(config, subject, measure)
% config needs only path_results_out; optional plot_dpi defaults to 150.
% Optionally pass the still-open failed figure as argument 4. It is neither
% modified nor closed. No analysis output is written, deleted, or truncated.
% Send this single file; no other MAGMA functions/toolboxes are required.

    if nargin < 4, failed_figure = []; end
    fprintf('\nMAGMA PNG diagnostic | %s\nMATLAB: %s\n', datestr(now, 30), version);
    fprintf('Platform: %s | pwd: %s\ntempdir: %s\n', computer, pwd, tempdir);
    report.environment = struct('matlab', version, 'platform', computer, ...
        'pwd', pwd, 'tempdir', tempdir);
    try
        report.environment.os = system_dependent('getos');
        fprintf('OS: %s\n', report.environment.os);
    catch ex
        report.environment.os_error = describe_exception(ex);
    end
    fprintf('exportgraphics implementation(s):\n');
    disp(which('exportgraphics', '-all'));
    fprintf('Screen size / pixels per inch:\n');
    disp(get(0, 'ScreenSize')); disp(get(0, 'ScreenPixelsPerInch'));

    % Same construction as load_raw_data and save_figure. Deliberately
    % recompute sub_results_path: load_raw_data also overwrites that field.
    folder = char(fullfile(config.path_results_out, ...
        ['Sub' num2str(subject) '_M' num2str(measure)]));
    stem = sprintf('Sub%d_M%d_shallow_breathing', subject, measure);
    target = fullfile(folder, [stem '.png']);
    report.target = target;
    fprintf('Exact analysis PNG target (NEVER written):\n%s\n', target);
    fprintf('Path length: %d | filename length: %d | spaces: %d | non-ASCII: %d\n', ...
        numel(target), numel([stem '.png']), any(target == ' '), any(double(target) > 127));
    fprintf('UNC syntax: %d | OneDrive name in path: %d\n', ...
        strncmp(target, '\\', 2), contains(lower(target), 'onedrive'));
    fprintf('Mapped drives/sync software cannot be established from the path alone.\n');
    fprintf('Relative paths resolve against the pwd printed above.\n');

    report.target_exists = isfile(target);
    report.target_is_folder = isfolder(target);
    report.target_openable = NaN;
    if report.target_exists
        [ok, attributes] = fileattrib(target);
        if ok, report.target_attributes = attributes; disp(attributes); end
        % r+ does not truncate. Open and close WITHOUT writing any bytes.
        [fid, message] = fopen(target, 'r+');
        report.target_openable = fid >= 0;
        if fid >= 0
            fclose(fid);
            fprintf('Existing target opened read/write WITHOUT modification.\n');
        else
            report.target_error = describe_exception(MException( ...
                'MAGMA:PNGDiagnostic:TargetNotWritable', '%s: %s', target, message));
        end
    else
        fprintf('Existing target: no file | target is a directory: %d\n', report.target_is_folder);
    end
    fprintf('An open check cannot rule out transient locks or later permission changes.\n');

    [report.output, cleanup_output] = inspect_folder(folder);
    [report.temp, cleanup_temp] = inspect_folder(tempdir);
    dpi = 150;
    if isfield(config, 'plot_dpi') && ~isempty(config.plot_dpi) && ...
            isscalar(config.plot_dpi) && isfinite(config.plot_dpi) && config.plot_dpi > 0
        dpi = config.plot_dpi;
    end
    fprintf('PNG resolution: %g DPI (same default as save_figure)\n', dpi);
    report.dpi = dpi;
    % Keep default tests small. An optional retained figure tests actual size
    % and complexity without rerunning any recording or altering that figure.
    report.tests = struct('kind', {}, 'folder', {}, 'path', {}, 'ok', {}, 'error', {}, 'short_name', {});
    for kind = {'simple', 'four_panel', 'retained_figure'}
        kind = kind{1};
        if strcmp(kind, 'retained_figure') && isempty(failed_figure), continue; end
        try
            if strcmp(kind, 'retained_figure')
                fig = failed_figure;
                assert(isscalar(fig) && isgraphics(fig, 'figure'), ...
                    'Argument 4 must be a valid figure handle.');
            else
                fig = synthetic_figure(kind);
                cleanup_figure = onCleanup(@() close(fig));
            end
            fprintf('%s figure: position %s | axes %d | graphics objects %d\n', ...
                kind, mat2str(get(fig, 'Position')), ...
                numel(findall(fig, 'Type', 'axes')), numel(findall(fig)));
            ax = findall(fig, 'Type', 'axes');
            try
                report.environment.graphics = rendererinfo(ax(1));
                disp(report.environment.graphics);
                if isfield(report.environment.graphics, 'Details')
                    disp(report.environment.graphics.Details);
                end
            catch ex
                report.environment.graphics_error = describe_exception(ex);
            end
            for location = {'output', 'temp'}
                state = report.(location{1});
                % Attempt export even if the generic write probe failed, to
                % retain the exporter's own exception. Fresh paths only.
                test = test_export(fig, state.folder, kind, numel(stem), dpi);
                report.tests(end + 1) = test;
            end
            if ~strcmp(kind, 'retained_figure'), clear cleanup_figure; end
        catch ex
            report.([kind '_setup_error']) = describe_exception(ex);
            if exist('cleanup_figure', 'var'), clear cleanup_figure; end
        end
    end
    fprintf('\nInterpretation (see docs/CONFIGURATION.md):\n');
    fprintf('A/B: bad path or mkdir/write failure; C: existing target cannot open r+.\n');
    fprintf('D: simple export fails in writable tempdir; E: only complex exports fail.\n');
    fprintf('All probes passing does NOT rule out a transient lock or the actual figure.\n');
    fprintf('Temporary PNGs/probes and newly created empty folders are cleaned up.\n');
end

function [state, cleanup] = inspect_folder(folder)
    state = struct('folder', folder, 'existed', isfolder(folder), ...
        'mkdir_ok', false, 'write_ok', false);
    fprintf('\nFolder: %s | existed: %d\n', folder, state.existed);
    missing = {};
    ancestor = folder;
    while ~isempty(ancestor) && ~isfolder(ancestor)
        missing{end + 1} = ancestor;
        parent = fileparts(ancestor);
        if strcmp(parent, ancestor), break; end
        ancestor = parent;
    end
    % Only rmdir EMPTY directories created by this run, leaf first.
    cleanup = onCleanup(@() remove_empty_folders(missing));
    try
        [ok, message, message_id] = mkdir(folder);
        fprintf('mkdir status: %d | id: %s | message: %s\n', ok, message_id, message);
        if ~ok
            error('MAGMA:PNGDiagnostic:MkdirFailed', '%s (%s)', message, message_id);
        end
        state.mkdir_ok = isfolder(folder);
        [ok, attributes] = fileattrib(folder);
        if ok, fprintf('Resolved folder: %s\n', attributes.Name); disp(attributes); end
        probe = fresh_path(folder, 12, '.tmp');
        write_probe(probe);
        state.write_ok = true;
        fprintf('Temporary file write: PASS\n');
    catch ex
        state.error = describe_exception(ex);
    end
end

function fig = synthetic_figure(kind)
    fig = figure('Visible', 'off', 'Units', 'pixels', ...
        'Position', [50 50 640 360], 'Color', 'w');
    try
        x = linspace(0, 30, 500);
        if strcmp(kind, 'simple')
            ax = axes('Parent', fig);
            plot(ax, x, sin(x)); title(ax, 'MAGMA simple PNG probe');
        else
            set(fig, 'Position', [50 50 1000 700]);
            tl = tiledlayout(fig, 4, 1, 'TileSpacing', 'compact', 'Padding', 'compact');
            title(tl, 'MAGMA synthetic amplitude diagnostic');
            for k = 1:4
                ax = nexttile(tl); hold(ax, 'on');
                patch(ax, [5 10 10 5], [-1 -1 1 1], [0.8 0.8 1], ...
                    'FaceAlpha', 0.2, 'EdgeColor', 'none');
                plot(ax, x, sin(x + k), 'k');
                scatter(ax, x(1:20:end), cos(x(1:20:end)), 10, 'filled');
                yline(ax, 0.5, 'r--'); grid(ax, 'on');
                legend(ax, {'support', 'signal', 'amplitude'}, 'Location', 'eastoutside');
            end
        end
        drawnow;
    catch ex
        close(fig); rethrow(ex);
    end
end

function test = test_export(fig, folder, kind, stem_length, dpi)
    filename = fresh_path(folder, stem_length, '.png');
    test = struct('kind', kind, 'folder', folder, 'path', filename, ...
        'ok', false, 'error', [], 'short_name', []);
    fprintf('\n%s export destination (%d characters):\n%s\n', kind, numel(filename), filename);
    cleanup = onCleanup(@() remove_file(filename));
    try
        exportgraphics(fig, filename, 'Resolution', dpi);
        info = imfinfo(filename);
        test.ok = strcmpi(info.Format, 'png') && info.Width > 0 && info.Height > 0;
        fprintf('Export PASS: %d x %d pixels\n', info.Width, info.Height);
    catch ex
        test.error = describe_exception(ex);
    end
    % A short name separates path-length/filename effects from directory access.
    if ~test.ok && stem_length > 8
        fprintf('Retry diagnostic ONLY with short fresh filename:\n');
        test.short_name = test_export(fig, folder, kind, 8, dpi);
    end
end

function filename = fresh_path(folder, stem_length, extension)
    while true
        [~, token] = fileparts(tempname);
        token = [token repmat('x', 1, stem_length)];
        filename = fullfile(folder, [token(1:stem_length) extension]);
        if ~isfile(filename) && ~isfolder(filename), return; end
    end
end

function detail = describe_exception(ex)
    detail = struct('identifier', ex.identifier, 'message', ex.message, ...
        'stack', ex.stack, 'report', getReport(ex, 'extended', 'hyperlinks', 'off'));
    fprintf('FAIL identifier: %s\n%s\n', ex.identifier, detail.report);
end

function remove_file(filename)
    if ~isfile(filename), return; end
    try
        delete(filename);
    catch ex
        fprintf('Cleanup failed for %s\n', filename); describe_exception(ex);
    end
end

function remove_empty_folders(folders)
    for k = 1:numel(folders)
        if isfolder(folders{k})
            [ok, message] = rmdir(folders{k}); % Never recursive, never delete contents.
            if ~ok, fprintf('Keeping folder %s: %s\n', folders{k}, message); end
        end
    end
end


function write_probe(probe)
    [fid, message] = fopen(probe, 'w');
    if fid < 0
        error('MAGMA:PNGDiagnostic:WriteFailed', '%s: %s', probe, message);
    end
    cleanup = onCleanup(@() close_and_remove(fid, probe));
    count = fwrite(fid, uint8('MAGMA PNG probe'), 'uint8');
    status = fclose(fid);
    if count ~= 15 || status ~= 0
        error('MAGMA:PNGDiagnostic:WriteFailed', 'Write/close failed: %s', probe);
    end

end


function close_and_remove(fid, probe)
    if strcmp(fopen(fid), probe), fclose(fid); end
    remove_file(probe);
end
