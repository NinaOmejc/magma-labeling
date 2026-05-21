function [event_sets, edit_info] = manual_edit_label_events(data, config, event_sets)
% manual_edit_label_events
% Final manual interval editor for label events, excluding sigh.
%
% This editor works at the event level. It can reuse persisted edits on
% rerun, lets the user drag on a non-shaded region to add an interval, and
% removes an existing interval when its shade is clicked.

    label_defs = manual_label_definitions();
    event_sets = ensure_event_sets(event_sets, label_defs);
    auto_event_sets = event_sets;

    cfg = label_edit_config(config);
    edit_file = manual_edit_file(config, cfg);
    N = size(data, 1);
    fs = config.new_fs;
    edit_info = init_edit_info(edit_file);

    if cfg.apply_saved_edits && exist(edit_file, 'file')
        loaded = load_manual_event_sets(edit_file, label_defs, config, N, fs);
        if ~isempty(loaded)
            event_sets = loaded;
            edit_info.applied_saved_edits = true;
            fprintf('Loaded manual label event edits: %s\n', edit_file);
        end
    end

    if ~cfg.manual_control
        edit_info = finalize_edit_info(edit_info, auto_event_sets, event_sets, label_defs);
        return;
    end

    event_sets = run_editor(data, config, event_sets, auto_event_sets, label_defs, cfg);
    edit_info.editor_opened = true;

    if cfg.save_edits
        save_manual_event_sets(edit_file, event_sets, label_defs, config, N, fs);
        fprintf('Saved manual label event edits: %s\n', edit_file);
    end
    edit_info = finalize_edit_info(edit_info, auto_event_sets, event_sets, label_defs);
end



function cfg = label_edit_config(config)
    cfg = struct();
    cfg.manual_control = false;
    cfg.apply_saved_edits = true;
    cfg.save_edits = true;
    cfg.window_sec = 300;
    cfg.min_interval_sec = 1;
    cfg.filename_suffix = '_manual_label_events.mat';

    if isfield(config, 'LabelEdit')
        names = fieldnames(cfg);
        for i = 1:numel(names)
            name = names{i};
            if isfield(config.LabelEdit, name) && ~isempty(config.LabelEdit.(name))
                cfg.(name) = config.LabelEdit.(name);
            end
        end
    end

    cfg.manual_control = logical(cfg.manual_control);
    cfg.apply_saved_edits = logical(cfg.apply_saved_edits);
    cfg.save_edits = logical(cfg.save_edits);
    cfg.window_sec = max(30, cfg.window_sec);
    cfg.min_interval_sec = max(0, cfg.min_interval_sec);
end

function edit_info = init_edit_info(edit_file)
    edit_info = struct( ...
        'edit_file', edit_file, ...
        'applied_saved_edits', false, ...
        'editor_opened', false, ...
        'changed_fields', {{}}, ...
        'changed_labels', {{}}, ...
        'changed_plot_names', {{}} );
end

function edit_info = finalize_edit_info(edit_info, auto_event_sets, event_sets, label_defs)
    changed = false(1, numel(label_defs));
    for i = 1:numel(label_defs)
        field = label_defs(i).field;
        changed(i) = ~event_sets_equal(auto_event_sets.(field), event_sets.(field));
    end

    edit_info.changed_fields = {label_defs(changed).field};
    edit_info.changed_labels = {label_defs(changed).name};
    edit_info.changed_plot_names = {label_defs(changed).plot_name};
end

function tf = event_sets_equal(a, b)
    a_table = event_signature_table(a);
    b_table = event_signature_table(b);
    tf = isequal(a_table, b_table);
end

function T = event_signature_table(events)
    if isempty(events)
        T = table(string.empty(0,1), zeros(0,1), zeros(0,1), zeros(0,1), zeros(0,1), ...
            'VariableNames', {'type', 'start_idx', 'end_idx', 'start_t', 'end_t'});
        return;
    end

    events = sanitize_events(events);
    event_type = string({events.type}');
    start_idx = round([events.start_idx]');
    end_idx = round([events.end_idx]');
    start_t = round([events.start_t]' * 1000) / 1000;
    end_t = round([events.end_t]' * 1000) / 1000;

    T = table(event_type, start_idx, end_idx, start_t, end_t, ...
        'VariableNames', {'type', 'start_idx', 'end_idx', 'start_t', 'end_t'});
    T = sortrows(T, {'type', 'start_idx', 'end_idx', 'start_t', 'end_t'});
end

function event_sets = ensure_event_sets(event_sets, label_defs)
    if nargin < 1 || isempty(event_sets) || ~isstruct(event_sets)
        event_sets = struct();
    end
    for i = 1:numel(label_defs)
        field = label_defs(i).field;
        if ~isfield(event_sets, field) || isempty(event_sets.(field))
            event_sets.(field) = empty_events();
        else
            event_sets.(field) = sanitize_events(event_sets.(field));
        end
    end
end

function events = sanitize_events(events)
    if isempty(events)
        events = empty_events();
        return;
    end

    template = empty_events();
    template(1).type = '';
    template(1).start_idx = 1;
    template(1).end_idx = 1;
    template(1).start_t = 0;
    template(1).end_t = 0;
    template(1).duration = 0;
    out = repmat(template, numel(events), 1);

    for i = 1:numel(events)
        out(i).type = char(string(get_event_field(events(i), 'type', '')));
        out(i).start_idx = get_event_field(events(i), 'start_idx', 1);
        out(i).end_idx = get_event_field(events(i), 'end_idx', out(i).start_idx);
        out(i).start_t = get_event_field(events(i), 'start_t', 0);
        out(i).end_t = get_event_field(events(i), 'end_t', out(i).start_t);
        out(i).duration = max(0, out(i).end_t - out(i).start_t);
    end
end

function value = get_event_field(event, field, default_value)
    value = default_value;
    if isfield(event, field) && ~isempty(event.(field))
        value = event.(field);
    end
end

function edit_file = manual_edit_file(config, cfg)
    if isfield(config, 'sub_results_path') && ~isempty(config.sub_results_path)
        out_dir = config.sub_results_path;
    else
        out_dir = config.path_results_out;
    end

    suffix = char(string(cfg.filename_suffix));
    edit_file = fullfile(out_dir, sprintf('Sub%d_M%d%s', config.subject, config.measure, suffix));
end

function loaded_sets = load_manual_event_sets(edit_file, label_defs, config, N, fs)
    loaded_sets = [];
    try
        loaded = load(edit_file);
    catch ME
        warning('MAGMA:ManualLabelEdit:LoadFailed', ...
            'Could not load manual label edits from %s: %s', edit_file, ME.message);
        return;
    end

    if ~isfield(loaded, 'manual_label_event_sets') || ~isfield(loaded, 'manual_label_edit_meta')
        warning('MAGMA:ManualLabelEdit:InvalidFile', ...
            'Ignoring manual label edit file without expected variables: %s', edit_file);
        return;
    end

    meta = loaded.manual_label_edit_meta;
    if ~is_valid_manual_meta(meta, config, N, fs)
        warning('MAGMA:ManualLabelEdit:MetaMismatch', ...
            'Ignoring manual label edits because subject, measurement, sample count, or sampling rate changed: %s', edit_file);
        return;
    end

    loaded_sets = ensure_event_sets(loaded.manual_label_event_sets, label_defs);
end

function ok = is_valid_manual_meta(meta, config, N, fs)
    ok = isstruct(meta) && ...
        isfield(meta, 'subject') && isequal(meta.subject, config.subject) && ...
        isfield(meta, 'measure') && isequal(meta.measure, config.measure) && ...
        isfield(meta, 'n_samples') && isequal(meta.n_samples, N) && ...
        isfield(meta, 'fs') && isequal(meta.fs, fs);
end

function save_manual_event_sets(edit_file, event_sets, label_defs, config, N, fs)
    out_dir = fileparts(edit_file);
    if ~isfolder(out_dir)
        mkdir(out_dir);
    end

    manual_label_event_sets = ensure_event_sets(event_sets, label_defs);
    manual_label_edit_meta = struct( ...
        'version', 1, ...
        'subject', config.subject, ...
        'measure', config.measure, ...
        'n_samples', N, ...
        'fs', fs, ...
        'data_columns', {config.data_columns}, ...
        'saved_on', char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss')) );

    save(edit_file, 'manual_label_event_sets', 'manual_label_edit_meta');
end

function event_sets = run_editor(data, config, event_sets, auto_event_sets, label_defs, cfg)
    if ~isfield(config, 'channels')
        config = resolve_signal_channels(config);
    end

    fs = config.new_fs;
    N = size(data, 1);
    t_raw = (0:N-1)' / fs;
    t_end = t_raw(end);
    window_sec = min(max(30, cfg.window_sec), max(30, t_end));
    current_label_idx = 1;
    drag_start_t = NaN;
    drag_active = false;
    drag_ax = gobjects(0);
    temp_patches = gobjects(0);

    idx_lungs = config.channels.lungs_idx;
    idx_diaph = config.channels.diaph_idx;
    idx_spo2 = config.channels.spo2_idx;

    fh = figure('Units', 'pixels', 'Position', near_fullscreen_figure_position(), 'Visible', 'on', ...
        'Name', 'Manual label event editor', 'NumberTitle', 'off');

    ax1 = subplot(3, 1, 1); hold(ax1, 'on');
    plot_trace_or_message(ax1, t_raw, data, idx_lungs, 'Resp-Lungs');
    title(ax1, 'Manual label editing: lungs');
    ylabel(ax1, 'Resp-Lungs'); grid(ax1, 'on');

    ax2 = subplot(3, 1, 2); hold(ax2, 'on');
    plot_trace_or_message(ax2, t_raw, data, idx_diaph, 'Resp-Diaphragm');
    title(ax2, 'Manual label editing: diaphragm');
    ylabel(ax2, 'Resp-Diaphragm'); grid(ax2, 'on');

    ax3 = subplot(3, 1, 3); hold(ax3, 'on');
    plot_trace_or_message(ax3, t_raw, data, idx_spo2, 'SpO2');
    title(ax3, 'Manual label editing: SpO2');
    ylabel(ax3, 'SpO2'); xlabel(ax3, 'Time (s)'); grid(ax3, 'on');

    ax = [ax1 ax2 ax3];
    for i = 1:numel(ax)
        set(ax(i), 'ButtonDownFcn', @(~,~) begin_drag(ax(i)));
    end
    linkaxes(ax, 'x');
    xlim(ax1, [0 min(window_sec, t_end)]);

    sgtitle(['MANUAL LABEL EVENT EDITING' newline ...
        'Subject: ' num2str(config.subject) ' | Measurement: ' num2str(config.measure)]);

    label_names = {label_defs.name};
    uicontrol(fh, 'Style', 'popupmenu', 'String', label_names, ...
        'Units', 'normalized', 'Position', [0.01 0.955 0.24 0.035], ...
        'Value', current_label_idx, 'Callback', @(src,~) change_label(src.Value));
    uicontrol(fh, 'Style', 'slider', 'Units', 'normalized', ...
        'Position', [0.10 0.01 0.55 0.03], 'Min', 0, ...
        'Max', max(0, t_end - window_sec), 'Value', 0, ...
        'SliderStep', slider_step(t_end, window_sec), ...
        'Callback', @(src,~) set_xlim(src.Value));
    uicontrol(fh, 'Style', 'pushbutton', 'String', 'Reset label', ...
        'Units', 'normalized', 'Position', [0.67 0.01 0.10 0.035], ...
        'Callback', @(~,~) reset_current_label());
    uicontrol(fh, 'Style', 'pushbutton', 'String', 'Reset all', ...
        'Units', 'normalized', 'Position', [0.78 0.01 0.10 0.035], ...
        'Callback', @(~,~) reset_all_labels());
    uicontrol(fh, 'Style', 'pushbutton', 'String', 'Done', ...
        'Units', 'normalized', 'Position', [0.89 0.01 0.10 0.035], ...
        'Callback', @(~,~) finish_editing());

    set(fh, 'WindowButtonMotionFcn', @(~,~) update_drag());
    set(fh, 'WindowButtonUpFcn', @(~,~) finish_drag());
    set(fh, 'CloseRequestFcn', @(~,~) finish_editing());

    fprintf('\nManual label event editor ON.\n');
    fprintf('  Choose a label from the dropdown.\n');
    fprintf('  Drag on a non-shaded area to add an interval for that label.\n');
    fprintf('  Click a shaded interval to remove it for the selected label.\n');
    fprintf('  Close or press Done when finished.\n\n');

    refresh_event_patches();
    uiwait(fh);
    if isgraphics(fh)
        delete(fh);
    end

    function steps = slider_step(total_sec, visible_sec)
        max_val = max(0, total_sec - visible_sec);
        if max_val <= 0
            steps = [1 1];
        else
            steps = [min(1 / max_val, 0.05) min(visible_sec / max_val, 1)];
        end
    end

    function set_xlim(x0)
        x0 = max(0, min(x0, max(0, t_end - window_sec)));
        xlim(ax1, [x0 min(x0 + window_sec, t_end)]);
    end

    function change_label(value)
        current_label_idx = value;
        refresh_event_patches();
    end

    function reset_current_label()
        field = label_defs(current_label_idx).field;
        event_sets.(field) = auto_event_sets.(field);
        refresh_event_patches();
    end

    function reset_all_labels()
        event_sets = auto_event_sets;
        refresh_event_patches();
    end

    function begin_drag(clicked_ax)
        if ~strcmp(get(fh, 'SelectionType'), 'normal')
            return;
        end
        t_click = current_axis_time(clicked_ax);
        if ~isfinite(t_click)
            return;
        end
        drag_start_t = clamp_time(t_click);
        drag_active = true;
        drag_ax = clicked_ax;
        delete_temp_patches();
    end

    function update_drag()
        if ~drag_active || ~isgraphics(fh)
            return;
        end
        if ~isgraphics(drag_ax)
            return;
        end
        t_now = current_axis_time(drag_ax);
        if ~isfinite(t_now)
            return;
        end
        draw_temp_interval(drag_start_t, clamp_time(t_now));
    end

    function finish_drag()
        if ~drag_active
            return;
        end
        drag_active = false;
        if isgraphics(drag_ax)
            t_stop = current_axis_time(drag_ax);
        else
            t_stop = NaN;
        end
        delete_temp_patches();
        if ~isfinite(t_stop) || ~isfinite(drag_start_t)
            return;
        end
        add_interval(drag_start_t, t_stop);
        drag_start_t = NaN;
    end

    function add_interval(t0, t1)
        t0 = clamp_time(t0);
        t1 = clamp_time(t1);
        if t1 < t0
            tmp = t0;
            t0 = t1;
            t1 = tmp;
        end
        if (t1 - t0) < cfg.min_interval_sec
            return;
        end

        field = label_defs(current_label_idx).field;
        ev = make_event(label_defs(current_label_idx).type, t0, t1, N, fs);
        event_sets.(field) = [event_sets.(field); ev];
        event_sets.(field) = sort_events_by_time(event_sets.(field));
        refresh_event_patches();
    end

    function remove_events_at_time(target_ax, fallback_index)
        field = label_defs(current_label_idx).field;
        events = event_sets.(field);
        if isempty(events)
            return;
        end

        t_click = current_axis_time(target_ax);
        if ~isfinite(t_click) && fallback_index >= 1 && fallback_index <= numel(events)
            t_click = 0.5 * (events(fallback_index).start_t + events(fallback_index).end_t);
        end
        if ~isfinite(t_click)
            return;
        end

        remove = [events.start_t] <= t_click & [events.end_t] >= t_click;
        if ~any(remove) && fallback_index >= 1 && fallback_index <= numel(events)
            remove(fallback_index) = true;
        end

        events(remove) = [];
        event_sets.(field) = events;
        refresh_event_patches();
    end

    function refresh_event_patches()
        delete(findall(fh, 'Tag', 'ManualLabelEventPatch'));
        delete_temp_patches();

        field = label_defs(current_label_idx).field;
        events = event_sets.(field);
        for ie = 1:numel(events)
            for ia = 1:numel(ax)
                add_event_patch(ax(ia), events(ie), ie);
            end
        end
        title(ax1, sprintf('Manual label editing: lungs | %s', label_defs(current_label_idx).name));
        title(ax2, sprintf('Manual label editing: diaphragm | %s', label_defs(current_label_idx).name));
        title(ax3, sprintf('Manual label editing: SpO2 | %s', label_defs(current_label_idx).name));
        align_axes_x_widths(ax);
        drawnow;
    end

    function add_event_patch(target_ax, ev, event_index)
        y_limits = ylim(target_ax);
        p = patch(target_ax, [ev.start_t ev.end_t ev.end_t ev.start_t], ...
            [y_limits(1) y_limits(1) y_limits(2) y_limits(2)], ...
            [1.00 0.65 0.65], 'FaceAlpha', 0.45, 'EdgeColor', 'none', ...
            'Tag', 'ManualLabelEventPatch', ...
            'ButtonDownFcn', @(~,~) remove_events_at_time(target_ax, event_index));
        set(p, 'HitTest', 'on', 'PickableParts', 'visible');
        try
            uistack(p, 'bottom');
        catch
        end
    end

    function draw_temp_interval(t0, t1)
        delete_temp_patches();
        if t1 < t0
            tmp = t0;
            t0 = t1;
            t1 = tmp;
        end
        for ia = 1:numel(ax)
            y_limits = ylim(ax(ia));
            temp_patches(end+1,1) = patch(ax(ia), [t0 t1 t1 t0], ...
                [y_limits(1) y_limits(1) y_limits(2) y_limits(2)], ...
                [0.45 0.70 1.00], 'FaceAlpha', 0.35, 'EdgeColor', 'none', ...
                'Tag', 'ManualLabelTempPatch', 'HitTest', 'off'); %#ok<AGROW>
        end
        drawnow limitrate;
    end

    function delete_temp_patches()
        if ~isempty(temp_patches)
            delete(temp_patches(isgraphics(temp_patches)));
        end
        temp_patches = gobjects(0);
        if isgraphics(fh)
            delete(findall(fh, 'Tag', 'ManualLabelTempPatch'));
        end
    end

    function t = current_axis_time(target_ax)
        cp = get(target_ax, 'CurrentPoint');
        if isempty(cp)
            t = NaN;
        else
            t = cp(1,1);
        end
    end

    function t = clamp_time(t)
        t = max(0, min(t_end, t));
    end

    function finish_editing()
        if isgraphics(fh)
            uiresume(fh);
        end
    end
end

function plot_trace_or_message(ax, t_raw, data, idx, label_text)
    if isempty(idx)
        text(ax, 0.5, 0.5, [label_text ' channel not found'], ...
            'Units', 'normalized', 'HorizontalAlignment', 'center');
        return;
    end

    h = plot(ax, t_raw, data(:, idx), 'k');
    set(h, 'HitTest', 'off', 'PickableParts', 'none');
end

function ev = make_event(event_type, start_t, end_t, N, fs)
    start_idx = max(1, min(N, round(start_t * fs) + 1));
    end_idx = max(1, min(N, round(end_t * fs) + 1));
    if end_idx < start_idx
        tmp = start_idx;
        start_idx = end_idx;
        end_idx = tmp;
    end

    start_t = (start_idx - 1) / fs;
    end_t = (end_idx - 1) / fs;
    ev = struct( ...
        'type', event_type, ...
        'start_idx', start_idx, ...
        'end_idx', end_idx, ...
        'start_t', start_t, ...
        'end_t', end_t, ...
        'duration', end_t - start_t);
end

function events = sort_events_by_time(events)
    if numel(events) <= 1
        return;
    end
    [~, order] = sort([events.start_t]);
    events = events(order);
end
