function [reviewed_event_sets, edit_info] = manual_edit_label_events(data, config, weak_event_sets)
% manual_edit_label_events
% Final manual interval editor for label events, excluding sigh. Automatic
% events are immutable input; a separate reviewed working copy and
% explicit per-label review scope are returned.
%
% This editor works at the event level. It can reuse persisted edits on
% rerun, lets the user drag on a non-shaded region to add an interval, and
% removes an existing interval when its shade is clicked.
% Click times and saved sample indices use the config.fs master timeline.

    label_defs = manual_label_definitions();
    N = size(data, 1);
    fs = config.fs;
    weak_event_sets = ensure_event_sets(weak_event_sets, label_defs, fs, N);
    cfg = label_edit_config(config);
    edit_file = manual_edit_file(config, cfg);
    edit_info = init_edit_info(edit_file);
    reviewed_event_sets = weak_event_sets;
    loaded_event_sets = [];
    review_history = empty_review_history();
    active_round_id = NaN;

    should_load = exist(edit_file, 'file') && ...
        (cfg.manual_control || cfg.apply_saved_edits || ...
         strcmp(cfg.start_from, 'latest_reviewed'));
    if should_load
        [loaded, ~, loaded_schema, ~, loaded_history, ...
            loaded_active_round_id] = load_manual_event_sets( ...
            edit_file, weak_event_sets, label_defs, config, N, fs);
        if ~isempty(loaded)
            loaded_event_sets = loaded;
            review_history = loaded_history;
            active_round_id = loaded_active_round_id;
            edit_info.loaded_schema_version = loaded_schema;
            fprintf('Loaded manual label review history: %s\n', edit_file);
        end
    end

    if ~cfg.manual_control
        if cfg.apply_saved_edits && ~isempty(loaded_event_sets)
            reviewed_event_sets = loaded_event_sets;
            edit_info.applied_saved_edits = true;
            edit_info = apply_active_round_info(edit_info, review_history, ...
                active_round_id, label_defs, N);
        else
            edit_info.review_history = empty_review_history();
            edit_info.review_provenance = make_review_provenance( ...
                edit_info.review_history, NaN);
        end
        return;
    end

    source_review_round = NaN;
    start_event_sets = weak_event_sets;
    if strcmp(cfg.start_from, 'latest_reviewed')
        if isempty(loaded_event_sets) || ~isfinite(active_round_id)
            error('MAGMA:ManualLabelEdit:MissingLatestReviewed', ...
                ['start_from is latest_reviewed, but no compatible active ' ...
                 'manual review is available for this recording.']);
        end
        start_event_sets = loaded_event_sets;
        source_review_round = active_round_id;
    end

    edited_event_sets = start_event_sets;
    new_coverage = false(N, numel(label_defs));
    [edited_event_sets, ~, new_coverage] = run_editor( ...
        data, config, edited_event_sets, weak_event_sets, start_event_sets, ...
        label_defs, cfg, {}, new_coverage);
    edit_info.editor_opened = true;

    round_meta = struct( ...
        'round_id', next_round_id(review_history), ...
        'reviewer_role', cfg.reviewer_role, ...
        'start_from', cfg.start_from, ...
        'source_review_round', source_review_round, ...
        'reviewer_id', cfg.reviewer_id, ...
        'notes', cfg.notes);
    [new_event_sets, new_round] = create_manual_review_round( ...
        start_event_sets, edited_event_sets, new_coverage, config, round_meta);
    review_history(end+1, 1) = new_round;

    if cfg.replace_reviewed || isempty(loaded_event_sets) || ~isfinite(active_round_id)
        reviewed_event_sets = new_event_sets;
        active_round_id = new_round.round_id;
    else
        review_history(end).accepted_as_active = false;
        reviewed_event_sets = loaded_event_sets;
    end

    if cfg.save_edits
        save_manual_event_sets(edit_file, weak_event_sets, reviewed_event_sets, ...
            review_history, active_round_id, label_defs, config, N, fs);
        fprintf('Saved manual label review round: %s\n', edit_file);
    end
    edit_info = apply_active_round_info(edit_info, review_history, ...
        active_round_id, label_defs, N);
end



function cfg = label_edit_config(config)
    cfg = struct();
    cfg.manual_control = false;
    cfg.apply_saved_edits = true;
    cfg.save_edits = true;
    cfg.window_sec = 300;
    cfg.min_interval_sec = 1;
    cfg.filename_suffix = '_manual_label_events.mat';
    cfg.start_from = 'automatic';
    cfg.replace_reviewed = true;
    cfg.reviewer_role = 'researcher';
    cfg.reviewer_id = '';
    cfg.notes = '';

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
    cfg.replace_reviewed = logical(cfg.replace_reviewed);
    cfg.window_sec = max(30, cfg.window_sec);
    cfg.min_interval_sec = max(0, cfg.min_interval_sec);
    cfg.start_from = char(string(cfg.start_from));
    if ~ismember(cfg.start_from, {'automatic', 'latest_reviewed'})
        error('MAGMA:ManualLabelEdit:InvalidStartFrom', ...
            'LabelEdit.start_from must be automatic or latest_reviewed.');
    end
    cfg.reviewer_role = strtrim(char(string(cfg.reviewer_role)));
    if isempty(cfg.reviewer_role), cfg.reviewer_role = 'unknown'; end
    cfg.reviewer_id = char(string(cfg.reviewer_id));
    cfg.notes = char(string(cfg.notes));
end

function edit_info = init_edit_info(edit_file)
    edit_info = struct( ...
        'edit_file', edit_file, ...
        'applied_saved_edits', false, ...
        'loaded_schema_version', NaN, ...
        'editor_opened', false, ...
        'start_from', '', ...
        'source_review_round', NaN, ...
        'reviewer_role', '', ...
        'review_scope', 'explicitly_viewed_or_edited_regions_per_label', ...
        'review_coverage_mask', false(0, 0), ...
        'reviewed_fields', {{}}, ...
        'reviewed_labels', {{}}, ...
        'status_by_label', struct(), ...
        'changed_fields', {{}}, ...
        'changed_labels', {{}}, ...
        'changed_plot_names', {{}} );
    edit_info.review_history = empty_review_history();
    edit_info.review_provenance = make_review_provenance( ...
        edit_info.review_history, NaN);
end

function edit_info = apply_active_round_info(edit_info, history, active_round_id, defs, N)
    edit_info.review_history = history;
    edit_info.review_provenance = make_review_provenance(history, active_round_id);
    edit_info.review_coverage_mask = false(N, numel(defs));
    status = struct();
    for i = 1:numel(defs), status.(defs(i).field) = 'unreviewed'; end

    active_index = find([history.round_id] == active_round_id, 1, 'last');
    if isempty(active_index)
        edit_info.status_by_label = status;
        return;
    end
    active = history(active_index);
    label_names = canonical_label_names();
    reviewed = false(1, numel(defs));
    changed = false(1, numel(defs));
    for i = 1:numel(defs)
        label_index = find(strcmp(label_names, defs(i).type), 1);
        edit_info.review_coverage_mask(:, i) = active.review_mask(:, label_index);
        reviewed(i) = any(edit_info.review_coverage_mask(:, i));
        status.(defs(i).field) = active.review_status{label_index};
        changed(i) = any(strcmp(active.changed_labels, defs(i).type));
    end
    edit_info.start_from = active.start_from;
    edit_info.source_review_round = active.source_review_round;
    edit_info.reviewer_role = active.reviewer_role;
    edit_info.reviewed_fields = {defs(reviewed).field};
    edit_info.reviewed_labels = {defs(reviewed).type};
    edit_info.status_by_label = status;
    edit_info.changed_fields = {defs(changed).field};
    edit_info.changed_labels = {defs(changed).name};
    edit_info.changed_plot_names = {defs(changed).plot_name};
end

function event_sets = ensure_event_sets(source_sets, label_defs, fs, N)
    if nargin < 3, fs = []; end
    if nargin < 4, N = []; end
    event_sets = struct();
    if nargin < 1 || isempty(source_sets) || ~isstruct(source_sets)
        source_sets = struct();
    end
    source_fields = fieldnames(source_sets);
    mapped_fields = canonicalize_label_names(source_fields);
    for i = 1:numel(label_defs)
        field = label_defs(i).field;
        source_index = find(strcmp(mapped_fields, field), 1);
        if isempty(source_index) || isempty(source_sets.(source_fields{source_index}))
            event_sets.(field) = empty_events();
        else
            event_sets.(field) = sanitize_events( ...
                source_sets.(source_fields{source_index}), fs, N);
        end
    end
end

function events = sanitize_events(events, fs, N)
    if nargin < 2, fs = []; end
    if nargin < 3, N = []; end
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
        out(i).start_idx = round(get_event_field(events(i), 'start_idx', 1));
        out(i).end_idx = round(get_event_field(events(i), 'end_idx', out(i).start_idx));
        if ~isempty(N)
            out(i).start_idx = max(1, min(N, out(i).start_idx));
            out(i).end_idx = max(out(i).start_idx, min(N, out(i).end_idx));
        end
        if isempty(fs)
            out(i).start_t = get_event_field(events(i), 'start_t', 0);
            out(i).end_t = get_event_field(events(i), 'end_t', out(i).start_t);
            out(i).duration = max(0, out(i).end_t - out(i).start_t);
        else
            out(i).start_t = (out(i).start_idx - 1) / fs;
            out(i).end_t = out(i).end_idx / fs;
            out(i).duration = ...
                (out(i).end_idx - out(i).start_idx + 1) / fs;
        end
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

function [loaded_sets, reviewed_fields, schema_version, review_coverage_mask, ...
    review_history, active_round_id] = load_manual_event_sets( ...
    edit_file, automatic_sets, label_defs, config, N, fs)
    loaded_sets = [];
    reviewed_fields = {};
    schema_version = NaN;
    review_coverage_mask = false(N, numel(label_defs));
    review_history = empty_review_history();
    active_round_id = NaN;
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
    if isfield(meta, 'schema_version') && isnumeric(meta.schema_version) && isscalar(meta.schema_version)
        schema_version = meta.schema_version;
    elseif isfield(meta, 'version') && isnumeric(meta.version) && isscalar(meta.version)
        schema_version = meta.version;
    end

    saved_sets = loaded.manual_label_event_sets;
    if ~isstruct(saved_sets)
        warning('MAGMA:ManualLabelEdit:InvalidFile', ...
            'Ignoring manual label edit file with invalid event sets: %s', edit_file);
        return;
    end

    % Field identity is authoritative across schema versions. Historical
    % compound raw types inside a historical rapid field are migrated to
    % canonical rapid without
    % reconstructing former depth/desaturation modifiers. A field absent
    % from an old file was never reviewed, so keep that label's current
    % automatic events rather than treating absence as a negative edit.
    loaded_sets = ensure_event_sets(automatic_sets, label_defs, fs, N);
    saved_fields = fieldnames(saved_sets);
    mapped_saved_fields = canonicalize_label_names(saved_fields);
    for i = 1:numel(label_defs)
        field = label_defs(i).field;
        saved_index = find(strcmp(mapped_saved_fields, field), 1);
        if isempty(saved_index)
            continue;
        end
        migrated = sanitize_events(saved_sets.(saved_fields{saved_index}), fs, N);
        for j = 1:numel(migrated)
            migrated(j).type = label_defs(i).type;
        end
        loaded_sets.(field) = migrated;
    end

    % Versions 1 and 2 did not persist review coverage. Their intervals may
    % migrate, but their absent scope cannot become a reviewed-negative claim.
    if schema_version >= 3 && isfield(loaded, 'manual_label_review_mask') && ...
            (isnumeric(loaded.manual_label_review_mask) || ...
             islogical(loaded.manual_label_review_mask)) && ...
            size(loaded.manual_label_review_mask, 1) == N && ...
            isfield(meta, 'label_names') && ...
            numel(meta.label_names) == size(loaded.manual_label_review_mask, 2)
        saved_review_labels = canonicalize_label_names(meta.label_names);
        saved_review_mask = logical(loaded.manual_label_review_mask);
        for i = 1:numel(label_defs)
            saved_index = find(strcmp(saved_review_labels, label_defs(i).type), 1);
            if ~isempty(saved_index)
                review_coverage_mask(:, i) = saved_review_mask(:, saved_index);
            end
        end
        reviewed_fields = {label_defs(any(review_coverage_mask, 1)).field};
    elseif schema_version >= 3 && isfield(loaded, 'manual_label_review_mask')
        warning('MAGMA:ManualLabelEdit:MissingLabelIdentity', ...
            ['Manual review coverage was not migrated because its saved ' ...
             'label_names are missing or misaligned. Event edits remain migrated by field identity.']);
    end

    if isfield(loaded, 'manual_label_review_history') && ...
            isstruct(loaded.manual_label_review_history) && ...
            ~isempty(loaded.manual_label_review_history)
        review_history = normalize_saved_review_history( ...
            loaded.manual_label_review_history, N, config);
        if ~isempty(review_history)
            if isfield(loaded, 'manual_label_active_round_id') && ...
                    isnumeric(loaded.manual_label_active_round_id) && ...
                    isscalar(loaded.manual_label_active_round_id)
                active_round_id = loaded.manual_label_active_round_id;
            elseif isfield(meta, 'active_round_id') && ...
                    isnumeric(meta.active_round_id) && isscalar(meta.active_round_id)
                active_round_id = meta.active_round_id;
            else
                active_round_id = review_history(end).round_id;
            end
            active_index = find([review_history.round_id] == active_round_id, 1, 'last');
            if isempty(active_index)
                warning('MAGMA:ManualLabelEdit:InvalidActiveRound', ...
                    'Saved active round is missing; using the most recent review round.');
                active_index = numel(review_history);
                active_round_id = review_history(active_index).round_id;
            end
            loaded_sets = event_sets_from_review_round( ...
                review_history(active_index), label_defs, fs, N);
            review_coverage_mask = generic_coverage_from_round( ...
                review_history(active_index), label_defs, N);
            reviewed_fields = {label_defs(any(review_coverage_mask, 1)).field};
            return;
        end
    end

    % A pre-history file is represented as an immutable first round. When
    % exact historical coverage was not stored, its review mask remains
    % false rather than inventing reviewed-negative regions.
    saved_timestamp = 'unknown';
    if isfield(meta, 'saved_on') && ~isempty(meta.saved_on)
        saved_timestamp = char(string(meta.saved_on));
    end
    legacy_meta = struct('round_id', 1, 'timestamp', saved_timestamp, ...
        'reviewer_role', 'unknown', 'start_from', 'automatic', ...
        'source_review_round', NaN, 'reviewer_id', '', ...
        'notes', sprintf('Migrated from manual-review schema %g.', schema_version));
    [~, legacy_round] = create_manual_review_round(loaded_sets, loaded_sets, ...
        review_coverage_mask, config, legacy_meta);
    [~, comparison] = create_manual_review_round(automatic_sets, loaded_sets, ...
        review_coverage_mask, config, legacy_meta);
    legacy_round.review_status = comparison.review_status;
    legacy_round.changed_labels = comparison.changed_labels;
    review_history = legacy_round;
    active_round_id = 1;
end

function ok = is_valid_manual_meta(meta, config, N, fs)
    ok = isstruct(meta) && ...
        isfield(meta, 'subject') && isequal(meta.subject, config.subject) && ...
        isfield(meta, 'measure') && isequal(meta.measure, config.measure) && ...
        isfield(meta, 'n_samples') && isequal(meta.n_samples, N) && ...
        isfield(meta, 'fs') && isequal(meta.fs, fs);
end

function history = normalize_saved_review_history(saved_history, N, config)
    history = empty_review_history();
    required = {'round_id', 'timestamp', 'reviewer_role', 'start_from', ...
        'source_review_round', 'events', 'mask', 'review_mask', ...
        'review_status', 'changed_labels'};
    if ~all(isfield(saved_history, required))
        warning('MAGMA:ManualLabelEdit:InvalidHistory', ...
            'Saved review history is missing required fields; migrating the active state instead.');
        return;
    end

    L = numel(canonical_label_names());
    normalized = repmat(review_round_template(), numel(saved_history), 1);
    for i = 1:numel(saved_history)
        source = saved_history(i);
        if ~isequal(size(source.mask), [N L]) || ...
                ~isequal(size(source.review_mask), [N L]) || ...
                numel(source.review_status) ~= L
            warning('MAGMA:ManualLabelEdit:InvalidHistory', ...
                'Saved review round %d has misaligned masks or status; migrating the active state instead.', i);
            return;
        end
        if ~isnumeric(source.round_id) || ~isscalar(source.round_id) || ...
                ~isfinite(source.round_id) || source.round_id < 1
            warning('MAGMA:ManualLabelEdit:InvalidHistory', ...
                'Saved review round %d has an invalid round id.', i);
            return;
        end
        start_from = char(string(source.start_from));
        if ~ismember(start_from, {'automatic', 'latest_reviewed'})
            warning('MAGMA:ManualLabelEdit:InvalidHistory', ...
                'Saved review round %d has an invalid start source.', i);
            return;
        end

        normalized(i).round_id = round(source.round_id);
        normalized(i).timestamp = char(string(source.timestamp));
        normalized(i).reviewer_role = char(string(source.reviewer_role));
        normalized(i).start_from = start_from;
        normalized(i).source_review_round = source.source_review_round;
        normalized(i).events = normalize_event_types_and_meta(source.events, config.fs);
        normalized(i).mask = logical(source.mask);
        normalized(i).review_mask = logical(source.review_mask);
        normalized(i).review_status = reshape(cellstr(string(source.review_status)), 1, []);
        normalized(i).changed_labels = reshape(cellstr(string(source.changed_labels)), 1, []);
        normalized(i).reviewer_id = optional_text(source, 'reviewer_id');
        normalized(i).notes = optional_text(source, 'notes');
        normalized(i).schema_version = optional_text( ...
            source, 'schema_version', 'manual_review_round_v1');
        if isfield(source, 'accepted_as_active') && ...
                isscalar(source.accepted_as_active)
            normalized(i).accepted_as_active = logical(source.accepted_as_active);
        end
    end
    if numel(unique([normalized.round_id])) ~= numel(normalized)
        warning('MAGMA:ManualLabelEdit:InvalidHistory', ...
            'Saved review history contains duplicate round ids.');
        return;
    end
    history = normalized;
end

function value = optional_text(source, field, default_value)
    if nargin < 3, default_value = ''; end
    value = default_value;
    if isfield(source, field) && ~isempty(source.(field))
        value = char(string(source.(field)));
    end
end

function event_sets = event_sets_from_review_round(round_info, defs, fs, N)
    event_sets = struct();
    events = normalize_event_types_and_meta(round_info.events, fs);
    for i = 1:numel(defs)
        keep = strcmp({events.type}, defs(i).type);
        event_sets.(defs(i).field) = sanitize_events(events(keep), fs, N);
    end
end

function coverage = generic_coverage_from_round(round_info, defs, N)
    coverage = false(N, numel(defs));
    label_names = canonical_label_names();
    if ~isequal(size(round_info.review_mask), [N numel(label_names)])
        error('MAGMA:ManualLabelEdit:ReviewMaskAlignment', ...
            'Active review coverage must be N-by-11.');
    end
    for i = 1:numel(defs)
        label_index = find(strcmp(label_names, defs(i).type), 1);
        coverage(:, i) = logical(round_info.review_mask(:, label_index));
    end
end

function history = empty_review_history()
    history = repmat(review_round_template(), 0, 1);
end

function value = review_round_template()
    value = struct( ...
        'round_id', NaN, ...
        'timestamp', '', ...
        'reviewer_role', '', ...
        'start_from', '', ...
        'source_review_round', NaN, ...
        'events', {normalize_event_types_and_meta(empty_events())}, ...
        'mask', false(0, numel(canonical_label_names())), ...
        'review_mask', false(0, numel(canonical_label_names())), ...
        'review_status', {{}}, ...
        'changed_labels', {{}}, ...
        'reviewer_id', '', ...
        'notes', '', ...
        'schema_version', 'manual_review_round_v1', ...
        'accepted_as_active', true);
end

function round_id = next_round_id(history)
    if isempty(history)
        round_id = 1;
    else
        round_id = max([history.round_id]) + 1;
    end
end

function provenance = make_review_provenance(history, active_round_id)
    provenance = struct( ...
        'version', 'manual_review_provenance_v1', ...
        'latest_round_id', NaN, ...
        'latest_reviewer_role', 'none', ...
        'start_from', 'none', ...
        'source_review_round', NaN, ...
        'number_of_rounds', numel(history), ...
        'most_recent_round_id', NaN);
    if ~isempty(history)
        provenance.most_recent_round_id = history(end).round_id;
    end
    active_index = find([history.round_id] == active_round_id, 1, 'last');
    if isempty(active_index), return; end
    active = history(active_index);
    provenance.latest_round_id = active.round_id;
    provenance.latest_reviewer_role = active.reviewer_role;
    provenance.start_from = active.start_from;
    provenance.source_review_round = active.source_review_round;
end

function save_manual_event_sets(edit_file, weak_event_sets, reviewed_event_sets, ...
    review_history, active_round_id, label_defs, config, N, fs)
    out_dir = fileparts(edit_file);
    if ~isfolder(out_dir)
        mkdir(out_dir);
    end

    manual_label_weak_event_sets = ensure_event_sets(weak_event_sets, label_defs, fs, N);
    manual_label_event_sets = ensure_event_sets(reviewed_event_sets, label_defs, fs, N);
    active_index = find([review_history.round_id] == active_round_id, 1, 'last');
    if isempty(active_index)
        error('MAGMA:ManualLabelEdit:InvalidActiveRound', ...
            'Cannot save manual review without a valid active round.');
    end
    manual_label_review_mask = generic_coverage_from_round( ...
        review_history(active_index), label_defs, N);
    manual_label_review_history = review_history;
    manual_label_active_round_id = active_round_id;
    manual_label_review_provenance = make_review_provenance( ...
        review_history, active_round_id);
    reviewed_fields = {label_defs(any(manual_label_review_mask, 1)).field};
    manual_label_edit_meta = struct( ...
        'version', 5, ...
        'schema_version', 5, ...
        'subject', config.subject, ...
        'measure', config.measure, ...
        'n_samples', N, ...
        'fs', fs, ...
        'data_columns', {config.data_columns}, ...
        'active_round_id', active_round_id, ...
        'review_scope', 'explicitly_viewed_or_edited_regions_per_label', ...
        'reviewed_fields', {reviewed_fields}, ...
        'saved_on', char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss')) );
    manual_label_edit_meta.label_names = {label_defs.type};
    manual_label_edit_meta.canonical_label_names = canonical_label_names();

    save(edit_file, 'manual_label_weak_event_sets', ...
        'manual_label_event_sets', 'manual_label_review_mask', ...
        'manual_label_review_history', 'manual_label_active_round_id', ...
        'manual_label_review_provenance', 'manual_label_edit_meta');
end

function [event_sets, reviewed_fields, review_coverage_mask] = run_editor( ...
    data, config, event_sets, auto_event_sets, start_event_sets, label_defs, cfg, ...
    reviewed_fields, review_coverage_mask)
    if ~isfield(config, 'channels')
        config = resolve_signal_channels(config);
    end

    fs = config.fs;
    N = size(data, 1);
    t_raw = (0:N-1)' / fs;
    t_end = t_raw(end);
    window_sec = min(max(30, cfg.window_sec), max(30, t_end));
    current_label_idx = 1;
    reviewed = ismember({label_defs.field}, reviewed_fields);
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
    set_global_ylim_from_channel(ax1, data, idx_lungs);

    ax2 = subplot(3, 1, 2); hold(ax2, 'on');
    plot_trace_or_message(ax2, t_raw, data, idx_diaph, 'Resp-Diaphragm');
    title(ax2, 'Manual label editing: diaphragm');
    ylabel(ax2, 'Resp-Diaphragm'); grid(ax2, 'on');
    set_global_ylim_from_channel(ax2, data, idx_diaph);

    ax3 = subplot(3, 1, 3); hold(ax3, 'on');
    plot_trace_or_message(ax3, t_raw, data, idx_spo2, 'SpO2');
    title(ax3, 'Manual label editing: SpO2');
    ylabel(ax3, 'SpO2'); xlabel(ax3, 'Time (s)'); grid(ax3, 'on');
    set_global_ylim_from_channel(ax3, data, idx_spo2);

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
    uicontrol(fh, 'Style', 'pushbutton', 'String', 'Reset label to start', ...
        'Units', 'normalized', 'Position', [0.67 0.01 0.10 0.035], ...
        'Callback', @(~,~) reset_current_label());
    uicontrol(fh, 'Style', 'pushbutton', 'String', 'Reset all to start', ...
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
    fprintf('  Reset restores the configured starting annotations (%s).\n', cfg.start_from);
    fprintf('  Close or press Done when finished.\n\n');

    refresh_event_patches();
    mark_current_view_reviewed();
    uiwait(fh);
    mark_current_view_reviewed();
    if isgraphics(fh)
        delete(fh);
    end
    reviewed_fields = {label_defs(reviewed).field};

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
        mark_current_view_reviewed();
    end

    function change_label(value)
        current_label_idx = value;
        mark_current_view_reviewed();
        refresh_event_patches();
    end

    function reset_current_label()
        field = label_defs(current_label_idx).field;
        mark_current_view_reviewed();
        event_sets.(field) = start_event_sets.(field);
        refresh_event_patches();
    end

    function reset_all_labels()
        event_sets = start_event_sets;
        mark_current_view_reviewed();
        refresh_event_patches();
    end

    function mark_current_view_reviewed()
        if ~isgraphics(ax1), return; end
        limits = xlim(ax1);
        start_idx = max(1, min(N, floor(limits(1) * fs) + 1));
        end_idx = max(start_idx, min(N, ceil(limits(2) * fs)));
        review_coverage_mask(start_idx:end_idx, current_label_idx) = true;
        reviewed(current_label_idx) = true;
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

        remove = [events.start_t] <= t_click & [events.end_t] > t_click;
        if ~any(remove) && fallback_index >= 1 && fallback_index <= numel(events)
            remove(fallback_index) = true;
        end

        events(remove) = [];
        event_sets.(field) = events;
        refresh_event_patches();
    end

    function refresh_event_patches()
        delete(findall(fh, 'Tag', 'ManualLabelEventPatch'));
        delete(findall(fh, 'Tag', 'ManualLabelAutomaticPatch'));
        delete_temp_patches();

        field = label_defs(current_label_idx).field;
        if strcmp(cfg.start_from, 'latest_reviewed')
            automatic_events = auto_event_sets.(field);
            for ie = 1:numel(automatic_events)
                for ia = 1:numel(ax)
                    add_automatic_reference_patch(ax(ia), automatic_events(ie));
                end
            end
        end
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

    function add_automatic_reference_patch(target_ax, ev)
        y_limits = ylim(target_ax);
        p = patch(target_ax, [ev.start_t ev.end_t ev.end_t ev.start_t], ...
            [y_limits(1) y_limits(1) y_limits(2) y_limits(2)], ...
            'none', 'EdgeColor', [0.20 0.45 0.90], 'LineStyle', '--', ...
            'LineWidth', 1, 'Tag', 'ManualLabelAutomaticPatch', ...
            'HitTest', 'off', 'PickableParts', 'none');
        try
            uistack(p, 'bottom');
        catch
        end
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

function set_global_ylim_from_channel(ax, data, idx)
    if isempty(idx) || ~isgraphics(ax)
        return;
    end
    ylim(ax, compute_global_ylim(data(:, idx)));
end

function y_limits = compute_global_ylim(signal)
    signal = signal(isfinite(signal));
    if isempty(signal)
        y_limits = [-1, 1];
        return;
    end

    y_min = min(signal);
    y_max = max(signal);
    if y_min == y_max
        pad = max(1e-3, 0.05 * max(1, abs(y_min)));
    else
        pad = max(1e-3, 0.05 * (y_max - y_min));
    end
    y_limits = [y_min - pad, y_max + pad];
end

function ev = make_event(event_type, start_t, end_t, N, fs)
    start_idx = max(1, min(N, round(start_t * fs) + 1));
    end_idx = max(start_idx, min(N, round(end_t * fs)));
    if end_idx < start_idx
        tmp = start_idx;
        start_idx = end_idx;
        end_idx = tmp;
    end

    start_t = (start_idx - 1) / fs;
    end_t = end_idx / fs;
    ev = struct( ...
        'type', event_type, ...
        'start_idx', start_idx, ...
        'end_idx', end_idx, ...
        'start_t', start_t, ...
        'end_t', end_t, ...
        'duration', (end_idx - start_idx + 1) / fs);
end

function events = sort_events_by_time(events)
    if numel(events) <= 1
        return;
    end
    [~, order] = sort([events.start_t]);
    events = events(order);
end
