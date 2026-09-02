function group_table = build_group_label_table(config_or_results_path)
% build_group_label_table
% Join saved master-timeline label files into one group-level CSV summary.
%
% Usage:
%   build_group_label_table()
%   build_group_label_table(config)
%   build_group_label_table('D:\Projects\MAGMA\data_analyis\disorder_classification')

    if nargin < 1 || isempty(config_or_results_path)
        config = get_config();
        results_path = config.path_results_out;
    elseif isstruct(config_or_results_path)
        config = config_or_results_path;
        results_path = config.path_results_out;
    else
        config = struct();
        results_path = char(config_or_results_path);
    end

    files = dir(fullfile(results_path, 'Sub*_M*', '*_labels.mat'));
    files = filter_result_files(files, config);
    out_dir = fullfile(results_path, 'group_analysis');
    if ~isfolder(out_dir)
        mkdir(out_dir);
    end

    canonical_labels = current_canonical_labels(config);
    rows = {};
    all_fields = {};
    for i = 1:numel(files)
        label_file = fullfile(files(i).folder, files(i).name);
        row = label_file_to_summary_row(label_file, config, canonical_labels);
        rows{end+1} = row; %#ok<AGROW>
        all_fields = union(all_fields, fieldnames(row), 'stable');
    end

    if isempty(rows)
        group_table = table();
    else
        rows = fill_missing_fields(rows, all_fields);
        group_table = struct2table([rows{:}], 'AsArray', true);
    end

    out_csv = fullfile(out_dir, 'group_label_summary.csv');
    out_mat = fullfile(out_dir, 'group_label_summary.mat');
    writetable(group_table, out_csv);
    save(out_mat, 'group_table');
    write_measure_comparability_table(out_dir);
    fprintf('Saved group label summary: %s\n', out_csv);
end

function row = label_file_to_summary_row(label_file, config, canonical_labels)
    loaded = load(label_file);

    row = struct();
    row.label_file = label_file;
    [file_subject, file_measure] = parse_subject_measure(label_file);
    row.subject = get_loaded_value(loaded, 'subject', file_subject);
    row.measure = get_loaded_value(loaded, 'measure', file_measure);
    row.measurement = row.measure;
    row.subject_group = subject_group_for_subject(row.subject, config);
    row.label_schema_version = char(string( ...
        get_loaded_value(loaded, 'label_schema_version', 'legacy_unspecified')));
    if isfield(loaded, 'resp_ref')
        row = add_respiratory_reference_summary(row, loaded.resp_ref);
    else
        row = add_respiratory_reference_summary(row, []);
    end

    row = add_label_summaries(row, loaded, config, canonical_labels);

    saved_events = empty_events();
    if isfield(loaded, 'events')
        saved_events = loaded.events;
    end
    row = add_event_counts(row, saved_events, canonical_labels);

    if isfield(loaded, 'diagnostic_signals')
        row = add_diagnostic_summaries(row, loaded.diagnostic_signals);
    end

end

function row = add_label_summaries(row, loaded, config, canonical_labels)
    row.duration_sec = nan;
    saved_labels = {};
    if isfield(loaded, 'label_names')
        saved_labels = cellstr(string(loaded.label_names));
    end
    labels = union(canonical_labels, saved_labels, 'stable');
    available = saved_label_availability(loaded, saved_labels);

    if isfield(loaded, 'mask') && (isnumeric(loaded.mask) || islogical(loaded.mask))
        fs = get_results_fs(loaded, config);
        row.duration_sec = size(loaded.mask, 1) / fs;
    end

    for i = 1:numel(labels)
        label = labels{i};
        field_label = matlab.lang.makeValidName(label);
        available_field = ['label_' field_label '_available'];
        duration_field = ['label_' field_label '_duration_sec'];
        fraction_field = ['label_' field_label '_fraction'];
        row.(available_field) = 0;
        row.(duration_field) = nan;
        row.(fraction_field) = nan;

        saved_index = find(strcmp(saved_labels, label), 1);
        if isempty(saved_index) || saved_index > numel(available) || ...
                ~available(saved_index) || ~isfield(loaded, 'mask') || ...
                saved_index > size(loaded.mask, 2)
            continue;
        end

        row.(available_field) = 1;
        fs = get_results_fs(loaded, config);
        label_samples = nnz(loaded.mask(:, saved_index) ~= 0);
        row.(duration_field) = label_samples / fs;
        if isfinite(row.duration_sec) && row.duration_sec > 0
            row.(fraction_field) = row.(duration_field) / row.duration_sec;
        end
    end
end

function available = saved_label_availability(loaded, saved_labels)
    available = true(1, numel(saved_labels));
    if isfield(loaded, 'label_available') && ...
            (isnumeric(loaded.label_available) || islogical(loaded.label_available)) && ...
            numel(loaded.label_available) == numel(saved_labels)
        available = logical(loaded.label_available(:)');
    elseif isfield(loaded, 'input_config') && isstruct(loaded.input_config) && ...
            isfield(loaded.input_config, 'running_labels')
        available = ismember(saved_labels, cellstr(string(loaded.input_config.running_labels)));
    end
end

function labels = current_canonical_labels(config)
    if isfield(config, 'labels') && isfield(config.labels, 'short')
        labels = {config.labels.short};
        return;
    end
    current_config = get_config();
    labels = {current_config.labels.short};
end

function row = add_respiratory_reference_summary(row, resp_ref)
    row = add_belt_reference_fields(row, resp_ref, 'lungs');
    row = add_belt_reference_fields(row, resp_ref, 'diaph');

    row.change_pattern = '';
    if isstruct(resp_ref) && isfield(resp_ref, 'change_pattern')
        row.change_pattern = char(string(resp_ref.change_pattern));
    end
end

function row = add_belt_reference_fields(row, resp_ref, belt_name)
    prefix = [belt_name '_'];
    row.([prefix 'start_end_ratio']) = NaN;
    row.([prefix 'change_detected']) = NaN;
    row.([prefix 'change_t']) = NaN;
    row.([prefix 'change_ratio']) = NaN;
    row.([prefix 'quality']) = '';
    row.([prefix 'session_reference_raw_units']) = NaN;
    row.([prefix 'session_n_breaths']) = NaN;
    row.([prefix 'session_available']) = NaN;
    row.([prefix 'global_reference_raw_units']) = NaN;
    row.([prefix 'global_to_session_ratio']) = NaN;
    row.([prefix 'reference_quality']) = '';
    row.([prefix 'reference_action']) = '';

    if ~isstruct(resp_ref) || ~isfield(resp_ref, belt_name) || ...
            ~isstruct(resp_ref.(belt_name))
        return;
    end
    belt = resp_ref.(belt_name);
    row.([prefix 'start_end_ratio']) = get_struct_value(belt, 'end_to_start_ratio', NaN);
    row.([prefix 'change_detected']) = double(get_struct_value(belt, 'change_detected', false));
    row.([prefix 'change_t']) = get_struct_value(belt, 'change_t', NaN);
    row.([prefix 'change_ratio']) = get_struct_value(belt, 'change_ratio', NaN);
    row.([prefix 'quality']) = char(string(get_struct_value(belt, 'quality', '')));
    if isfield(belt, 'session') && isstruct(belt.session)
        row.([prefix 'session_reference_raw_units']) = ...
            get_struct_value(belt.session, 'value', NaN);
        row.([prefix 'session_n_breaths']) = ...
            get_struct_value(belt.session, 'n_breaths', NaN);
        row.([prefix 'session_available']) = double( ...
            get_struct_value(belt.session, 'available', false));
    end
    if isfield(belt, 'global') && isstruct(belt.global)
        row.([prefix 'global_reference_raw_units']) = ...
            get_struct_value(belt.global, 'value', NaN);
    end
    row.([prefix 'global_to_session_ratio']) = ...
        get_struct_value(belt, 'global_to_session_ratio', NaN);
    row.([prefix 'reference_quality']) = char(string( ...
        get_struct_value(belt, 'reference_quality', '')));
    row.([prefix 'reference_action']) = char(string( ...
        get_struct_value(belt, 'reference_action', '')));
end

function out_csv = write_measure_comparability_table(out_dir)
    measure_family = [ ...
        "respiratory_rate"; ...
        "event_duration_or_fraction"; ...
        "spo2"; ...
        "timing_measure"; ...
        "belt_amplitude_ratio"; ...
        "shallow_or_deep_excursion_ratio"; ...
        "global_to_session_amplitude_ratio"; ...
        "thoracic_to_abdominal_ratio"; ...
        "thoracic_dominance_log_ratio"; ...
        "thoracic_relative_fraction"; ...
        "raw_belt_amplitude"];
    comparability = [ ...
        "absolute_comparable_across_subjects"; ...
        "absolute_comparable_across_subjects"; ...
        "absolute_comparable_across_subjects"; ...
        "absolute_comparable_across_subjects"; ...
        "within_record_normalized"; ...
        "within_record_normalized"; ...
        "within_record_normalized"; ...
        "within_record_normalized"; ...
        "within_record_normalized"; ...
        "within_record_normalized"; ...
        "not_safely_comparable_across_subjects"];
    units_or_scale = [ ...
        "breaths_per_minute"; ...
        "seconds_or_fraction"; ...
        "percent"; ...
        "seconds"; ...
        "unitless_ratio"; ...
        "unitless_ratio"; ...
        "unitless_ratio"; ...
        "unitless_ratio"; ...
        "log_unitless_ratio"; ...
        "unitless_fraction"; ...
        "uncalibrated_belt_units"];
    interpretation = [ ...
        "Absolute respiratory rate"; ...
        "Absolute event burden or recording fraction"; ...
        "Absolute oxygen saturation"; ...
        "Absolute event or breath timing"; ...
        "Interpret only relative to the same recording's session reference"; ...
        "Interpret shallow/deep excursion only within the same recording"; ...
        "Whole-record amplitude relative to that recording's session reference"; ...
        "Ratio of independently session-normalized thoracic and abdominal excursion"; ...
        "Log of the within-record normalized thoracic/abdominal excursion ratio"; ...
        "Bounded within-record thoracic share of normalized excursion"; ...
        "Do not compare raw belt magnitude between subjects"];

    comparability_table = table(measure_family, comparability, units_or_scale, interpretation);
    out_csv = fullfile(out_dir, 'group_measure_comparability.csv');
    writetable(comparability_table, out_csv);
end

function value = get_struct_value(s, name, default_value)
    value = default_value;
    if isfield(s, name)
        value = s.(name);
    end
end

function value = get_loaded_value(loaded, field_name, default_value)
    if isfield(loaded, field_name)
        value = loaded.(field_name);
    else
        value = default_value;
    end
end

function fs = get_results_fs(loaded, config)
    fs = nan;
    if isfield(loaded, 'config') && isfield(loaded.config, 'fs')
        fs = loaded.config.fs;
    elseif isfield(config, 'fs')
        fs = config.fs;
    end
    if ~isfinite(fs) || fs <= 0
        fs = 1;
    end
end

function row = add_event_counts(row, events, canonical_labels)
    event_types = {};
    if ~isempty(events) && isfield(events, 'type')
        event_types = {events.type};
    end
    labels = union(canonical_labels, unique(event_types, 'stable'), 'stable');
    for i = 1:numel(labels)
        field_label = matlab.lang.makeValidName(labels{i});
        available_field = ['label_' field_label '_available'];
        count_field = ['events_' field_label '_count'];
        if isfield(row, available_field) && row.(available_field) == 1
            row.(count_field) = sum(strcmp(event_types, labels{i}));
        else
            row.(count_field) = nan;
        end
    end
end

function row = add_diagnostic_summaries(row, diagnostic_signals)
    row = add_numeric_struct_summaries(row, diagnostic_signals, ...
        'diagnostic', {'time_sec'});
end

function row = add_numeric_struct_summaries(row, source, prefix, skip_names)
    names = fieldnames(source);
    for i = 1:numel(names)
        name = names{i};
        if any(strcmp(name, skip_names))
            continue;
        end

        x = source.(name);
        if ~isnumeric(x)
            continue;
        end

        col = [prefix '_' matlab.lang.makeValidName(name)];
        if isscalar(x)
            row.(col) = x;
        else
            x = x(:);
            x = x(isfinite(x));
            if isempty(x)
                row.([col '_mean']) = nan;
                row.([col '_median']) = nan;
                row.([col '_p10']) = nan;
                row.([col '_p90']) = nan;
            else
                row.([col '_mean']) = mean(x, 'omitnan');
                row.([col '_median']) = median(x, 'omitnan');
                row.([col '_p10']) = prctile(x, 10);
                row.([col '_p90']) = prctile(x, 90);
                row.([col '_std']) = std(x, 'omitnan');
                med_x = median(x, 'omitnan');
                if isfinite(med_x) && med_x ~= 0
                    row.([col '_cv']) = std(x, 'omitnan') / abs(med_x);
                else
                    row.([col '_cv']) = nan;
                end
            end
        end
    end
end

function rows = fill_missing_fields(rows, all_fields)
    for i = 1:numel(rows)
        for j = 1:numel(all_fields)
            name = all_fields{j};
            if ~isfield(rows{i}, name)
                rows{i}.(name) = missing_value_for_field(name);
            end
        end
        rows{i} = orderfields(rows{i}, all_fields);
    end
end

function value = missing_value_for_field(name)
    if strcmp(name, 'label_file') || strcmp(name, 'subject_group') || ...
            strcmp(name, 'label_schema_version') || ...
            strcmp(name, 'change_pattern') || endsWith(name, '_quality') || ...
            endsWith(name, '_action')
        value = '';
    elseif startsWith(name, 'events_') && endsWith(name, '_count')
        value = nan;
    elseif startsWith(name, 'label_') && endsWith(name, '_available')
        value = 0;
    elseif startsWith(name, 'label_') && ...
            (endsWith(name, '_duration_sec') || endsWith(name, '_fraction'))
        value = nan;
    else
        value = nan;
    end
end

function files = filter_result_files(files, config)
    subjects = get_group_filter(config, 'subjects');
    measures = get_group_filter(config, 'measurements');

    if isempty(subjects) && isempty(measures)
        return;
    end

    keep = true(size(files));
    for i = 1:numel(files)
        [subject, measure] = parse_subject_measure(fullfile(files(i).folder, files(i).name));
        if ~isempty(subjects) && ~ismember(subject, subjects)
            keep(i) = false;
        end
        if ~isempty(measures) && ~ismember(measure, measures)
            keep(i) = false;
        end
    end
    files = files(keep);
end

function value = get_group_filter(config, name)
    value = [];
    if isfield(config, 'group') && isfield(config.group, name)
        value = config.group.(name);
    elseif isfield(config, name)
        value = config.(name);
    end
    value = value(:)';
end

function group_name = subject_group_for_subject(subject, config)
    group_name = 'Unknown';
    if isempty(subject) || ~isnumeric(subject) || ~isscalar(subject) || ~isfinite(subject)
        return;
    end

    control_subjects = get_subject_group_list(config, 'control_subjects');
    patient_subjects = get_subject_group_list(config, 'patient_subjects');

    if ismember(subject, control_subjects)
        group_name = 'Control';
    elseif ismember(subject, patient_subjects)
        group_name = 'Patient';
    end
end

function subjects = get_subject_group_list(config, name)
    subjects = [];
    if isfield(config, 'group') && isfield(config.group, name)
        subjects = config.group.(name);
    elseif isfield(config, name)
        subjects = config.(name);
    end
    subjects = subjects(:)';
end

function [subject, measure] = parse_subject_measure(label_file)
    subject = nan;
    measure = nan;
    [~, name] = fileparts(label_file);
    tok = regexp(name, 'Sub(\d+)_M(\d+)', 'tokens', 'once');
    if isempty(tok)
        tok = regexp(label_file, 'Sub(\d+)_M(\d+)', 'tokens', 'once');
    end
    if ~isempty(tok)
        subject = str2double(tok{1});
        measure = str2double(tok{2});
    end
end
