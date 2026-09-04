function group_table = build_group_label_table(config_or_results_path)
% BUILD_GROUP_LABEL_TABLE Build group label table.
%
% Syntax:
%   group_table = build_group_label_table(config_or_results_path)
%
% Inputs:
%   config_or_results_path - Configuration structure or results-directory path.
%
% Outputs:
%   group_table - Output table.

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
    event_duration_table = build_group_event_duration_table(files);
    localized_boundary_qc = build_group_boundary_qc_table(files);
    cohort_qc = build_cohort_qc_summary( ...
        group_table, canonical_labels, event_duration_table, localized_boundary_qc);
    save(fullfile(out_dir, 'cohort_qc_summary.mat'), 'cohort_qc');
    if ~isempty(cohort_qc.by_label)
        writetable(cohort_qc.by_label, ...
            fullfile(out_dir, 'cohort_label_qc_summary.csv'));
    end
    writetable(event_duration_table, ...
        fullfile(out_dir, 'cohort_event_durations.csv'));
    writetable(localized_boundary_qc, ...
        fullfile(out_dir, 'cohort_localized_boundary_qc.csv'));
    fprintf('Saved group label summary: %s\n', out_csv);
end

function row = label_file_to_summary_row(label_file, config, canonical_labels)
% LABEL_FILE_TO_SUMMARY_ROW Perform the label file to summary row operation.
%
% Syntax:
%   row = label_file_to_summary_row(label_file, config, canonical_labels)
%
% Inputs:
%   label_file - File or dataset path.
%   config - Pipeline configuration structure.
%   canonical_labels - Label identifier or label metadata.
%
% Outputs:
%   row - Computed output value `row`.

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
    if isfield(loaded, 'events_automatic')
        saved_events = loaded.events_automatic;
    end
    row = add_event_counts(row, saved_events, canonical_labels);
    row = add_annotation_provenance_summaries(row, loaded, config, canonical_labels);
    row = add_belt_availability_summary(row, loaded);
    row = add_overlap_summaries(row, loaded);

    if isfield(loaded, 'diagnostic_signals')
        row = add_diagnostic_summaries(row, loaded.diagnostic_signals);
    end

end

function row = add_label_summaries(row, loaded, config, canonical_labels)
% ADD_LABEL_SUMMARIES Add label summaries.
%
% Syntax:
%   row = add_label_summaries(row, loaded, config, canonical_labels)
%
% Inputs:
%   row - Input value `row`.
%   loaded - Input value `loaded`.
%   config - Pipeline configuration structure.
%   canonical_labels - Label identifier or label metadata.
%
% Outputs:
%   row - Computed output value `row`.

    row.duration_sec = nan;
    saved_labels = {};
    if isfield(loaded, 'label_names')
        saved_labels = canonicalize_label_names(loaded.label_names);
    end
    labels = canonical_labels;
    available = saved_label_availability(loaded, saved_labels);

    automatic_mask = get_saved_mask(loaded, 'mask_automatic');
    if ~isempty(automatic_mask)
        fs = get_results_fs(loaded, config);
        row.duration_sec = size(automatic_mask, 1) / fs;
    end

    for i = 1:numel(labels)
        label = labels{i};
        field_label = matlab.lang.makeValidName(label);
        available_field = ['label_' field_label '_available'];
        duration_field = ['label_' field_label '_duration_sec'];
        fraction_field = ['label_' field_label '_fraction'];
        automatic_duration_field = ['label_' field_label '_automatic_duration_sec'];
        automatic_fraction_field = ['label_' field_label '_automatic_fraction'];
        row.(available_field) = 0;
        row.(duration_field) = nan;
        row.(fraction_field) = nan;
        row.(automatic_duration_field) = nan;
        row.(automatic_fraction_field) = nan;

        saved_index = find(strcmp(saved_labels, label), 1);
        if isempty(saved_index) || saved_index > numel(available) || ...
                ~available(saved_index) || isempty(automatic_mask) || ...
                saved_index > size(automatic_mask, 2)
            continue;
        end

        row.(available_field) = 1;
        fs = get_results_fs(loaded, config);
        assessable = saved_assessable_column(loaded, size(automatic_mask, 1), ...
            numel(saved_labels), saved_index, available(saved_index));
        label_samples = nnz(automatic_mask(:, saved_index) ~= 0 & assessable);
        row.(duration_field) = label_samples / fs;
        if any(assessable)
            row.(fraction_field) = label_samples / nnz(assessable);
        end
        row.(automatic_duration_field) = row.(duration_field);
        row.(automatic_fraction_field) = row.(fraction_field);
    end
end

function row = add_annotation_provenance_summaries(row, loaded, config, canonical_labels)
% ADD_ANNOTATION_PROVENANCE_SUMMARIES Add annotation provenance summaries.
%
% Syntax:
%   row = add_annotation_provenance_summaries(row, loaded, config, canonical_labels)
%
% Inputs:
%   row - Input value `row`.
%   loaded - Input value `loaded`.
%   config - Pipeline configuration structure.
%   canonical_labels - Label identifier or label metadata.
%
% Outputs:
%   row - Computed output value `row`.

    saved_labels = canonical_labels;
    if isfield(loaded, 'label_names')
        saved_labels = canonicalize_label_names(loaded.label_names);
    end
    available = saved_label_availability(loaded, saved_labels);
    automatic_mask = get_saved_mask(loaded, 'mask_automatic');
    reviewed_mask = get_saved_mask(loaded, 'mask_reviewed');
    review_mask = get_saved_mask(loaded, 'gold_review_mask');
    fs = get_results_fs(loaded, config);
    automatic_events = get_saved_events(loaded, 'events_automatic');
    reviewed_events = get_saved_events(loaded, 'events_reviewed');

    for i = 1:numel(canonical_labels)
        label = canonical_labels{i};
        field_label = matlab.lang.makeValidName(label);
        row.(['label_' field_label '_reviewed_duration_sec']) = nan;
        row.(['label_' field_label '_reviewed_fraction']) = nan;
        row.(['label_' field_label '_reviewed_coverage_fraction']) = 0;
        row.(['label_' field_label '_automatic_reviewed_disagreement_fraction']) = nan;
        row.(['events_' field_label '_automatic_count']) = nan;
        row.(['events_' field_label '_reviewed_count']) = nan;
        row.(['events_' field_label '_automatic_duration_median_sec']) = nan;
        row.(['events_' field_label '_automatic_duration_p90_sec']) = nan;

        idx = find(strcmp(saved_labels, label), 1);
        if isempty(idx) || idx > numel(available) || ~available(idx) || ...
                isempty(automatic_mask) || idx > size(automatic_mask, 2)
            continue;
        end
        assessable = saved_assessable_column(loaded, size(automatic_mask, 1), ...
            numel(saved_labels), idx, true);
        automatic_values = logical(automatic_mask(:, idx));
        row.(['events_' field_label '_automatic_count']) = count_events(automatic_events, label);
        durations = event_durations(automatic_events, label, fs);
        if ~isempty(durations)
            row.(['events_' field_label '_automatic_duration_median_sec']) = median(durations, 'omitnan');
            row.(['events_' field_label '_automatic_duration_p90_sec']) = prctile(durations, 90);
        end
        if isempty(reviewed_mask) || isempty(review_mask) || ...
                idx > size(reviewed_mask, 2) || idx > size(review_mask, 2)
            continue;
        end
        reviewed_scope = logical(review_mask(:, idx)) & assessable;
        if any(assessable)
            row.(['label_' field_label '_reviewed_coverage_fraction']) = ...
                nnz(reviewed_scope) / nnz(assessable);
        end
        if ~any(reviewed_scope)
            continue;
        end
        reviewed_values = logical(reviewed_mask(:, idx));
        row.(['label_' field_label '_reviewed_duration_sec']) = ...
            nnz(reviewed_values & reviewed_scope) / fs;
        row.(['label_' field_label '_reviewed_fraction']) = ...
            nnz(reviewed_values & reviewed_scope) / nnz(reviewed_scope);
        row.(['label_' field_label '_automatic_reviewed_disagreement_fraction']) = ...
            nnz(xor(automatic_values, reviewed_values) & reviewed_scope) / nnz(reviewed_scope);
        row.(['events_' field_label '_reviewed_count']) = ...
            count_events(reviewed_events, label);
    end
end

function available = saved_label_availability(loaded, saved_labels)
% SAVED_LABEL_AVAILABILITY Perform the saved label availability operation.
%
% Syntax:
%   available = saved_label_availability(loaded, saved_labels)
%
% Inputs:
%   loaded - Input value `loaded`.
%   saved_labels - Label identifier or label metadata.
%
% Outputs:
%   available - Logical availability result.

    available = true(1, numel(saved_labels));
    if isfield(loaded, 'label_available') && ...
            (isnumeric(loaded.label_available) || islogical(loaded.label_available)) && ...
            numel(loaded.label_available) == numel(saved_labels)
        available = logical(loaded.label_available(:)');
    elseif isfield(loaded, 'input_config') && isstruct(loaded.input_config) && ...
            isfield(loaded.input_config, 'running_labels')
        running_labels = canonicalize_label_names(loaded.input_config.running_labels);
        available = ismember(saved_labels, running_labels);
    end
end

function mask = get_saved_mask(loaded, field)
% GET_SAVED_MASK Return saved mask.
%
% Syntax:
%   mask = get_saved_mask(loaded, field)
%
% Inputs:
%   loaded - Input value `loaded`.
%   field - Saved result field name.
%
% Outputs:
%   mask - Logical output mask.

    mask = [];
    if isfield(loaded, field) && ...
            (isnumeric(loaded.(field)) || islogical(loaded.(field)))
        mask = loaded.(field);
    end
end

function assessable = saved_assessable_column(loaded, N, L, idx, available)
% SAVED_ASSESSABLE_COLUMN Perform the saved assessable column operation.
%
% Syntax:
%   assessable = saved_assessable_column(loaded, N, L, idx, available)
%
% Inputs:
%   loaded - Input value `loaded`.
%   N - Number of samples.
%   L - Input value `L`.
%   idx - Input value `idx`.
%   available - Input value `available`.
%
% Outputs:
%   assessable - Computed output value `assessable`.

    assessable = repmat(logical(available), N, 1);
    if isfield(loaded, 'label_assessable_mask') && ...
            (isnumeric(loaded.label_assessable_mask) || ...
             islogical(loaded.label_assessable_mask)) && ...
            isequal(size(loaded.label_assessable_mask), [N L])
        assessable = logical(loaded.label_assessable_mask(:, idx));
    end
end

function events = get_saved_events(loaded, field)
% GET_SAVED_EVENTS Return saved events.
%
% Syntax:
%   events = get_saved_events(loaded, field)
%
% Inputs:
%   loaded - Input value `loaded`.
%   field - Saved result field name.
%
% Outputs:
%   events - Event structure array.

    events = empty_events();
    if isfield(loaded, field) && isstruct(loaded.(field))
        events = loaded.(field);
    end
end

function count = count_events(events, label)
% COUNT_EVENTS Perform the count events operation.
%
% Syntax:
%   count = count_events(events, label)
%
% Inputs:
%   events - Event structure data.
%   label - Label identifier or label metadata.
%
% Outputs:
%   count - Computed index or count value.

    count = 0;
    if ~isempty(events) && isfield(events, 'type')
        count = nnz(strcmp(canonicalize_label_names({events.type}), label));
    end
end

function durations = event_durations(events, label, fs)
% EVENT_DURATIONS Perform the event durations operation.
%
% Syntax:
%   durations = event_durations(events, label, fs)
%
% Inputs:
%   events - Event structure data.
%   label - Label identifier or label metadata.
%   fs - Sampling frequency in hertz.
%
% Outputs:
%   durations - Computed numeric value.

    durations = [];
    if isempty(events) || ~isfield(events, 'type')
        return;
    end
    keep = strcmp(canonicalize_label_names({events.type}), label);
    selected = events(keep);
    durations = nan(1, numel(selected));
    for i = 1:numel(selected)
        durations(i) = authoritative_event_duration(selected(i), fs);
    end
    durations = durations(isfinite(durations));
end

function row = add_belt_availability_summary(row, loaded)
% ADD_BELT_AVAILABILITY_SUMMARY Add belt availability summary.
%
% Syntax:
%   row = add_belt_availability_summary(row, loaded)
%
% Inputs:
%   row - Input value `row`.
%   loaded - Input value `loaded`.
%
% Outputs:
%   row - Computed output value `row`.

    lungs = false;
    diaph = false;
    if isfield(loaded, 'resp_features') && isstruct(loaded.resp_features) && ...
            isfield(loaded.resp_features, 'resp')
        resp = loaded.resp_features.resp;
    elseif isfield(loaded, 'phys_feat') && isstruct(loaded.phys_feat) && ...
            isfield(loaded.phys_feat, 'resp')
        resp = loaded.phys_feat.resp;
    else
        resp = struct();
    end
    if ~isempty(fieldnames(resp))
        if isfield(resp, 'lungs') && isfield(resp.lungs, 'available')
            lungs = logical(resp.lungs.available);
        end
        if isfield(resp, 'diaph') && isfield(resp.diaph, 'available')
            diaph = logical(resp.diaph.available);
        end
    end
    row.lungs_belt_available = double(lungs);
    row.diaph_belt_available = double(diaph);
    if lungs && diaph
        row.respiratory_belt_availability = 'two_belts';
    elseif lungs || diaph
        row.respiratory_belt_availability = 'single_belt';
    else
        row.respiratory_belt_availability = 'no_belt';
    end
end

function row = add_overlap_summaries(row, loaded)
% ADD_OVERLAP_SUMMARIES Add overlap summaries.
%
% Syntax:
%   row = add_overlap_summaries(row, loaded)
%
% Inputs:
%   row - Input value `row`.
%   loaded - Input value `loaded`.
%
% Outputs:
%   row - Computed output value `row`.

    layers = {'automatic', 'reviewed'};
    fields = {'label_overlap_summary_automatic', 'label_overlap_summary_reviewed'};
    for i = 1:numel(layers)
        if ~isfield(loaded, fields{i}) || ~isstruct(loaded.(fields{i}))
            continue;
        end
        summary = loaded.(fields{i});
        pairs = setdiff(fieldnames(summary), {'version'});
        for j = 1:numel(pairs)
            pair = summary.(pairs{j});
            if ~isstruct(pair), continue; end
            prefix = ['overlap_' layers{i} '_' pairs{j} '_'];
            numeric_fields = {'available', 'overlap_duration_sec', ...
                'fraction_of_a_overlapped_by_b', 'fraction_of_b_overlapped_by_a'};
            for k = 1:numel(numeric_fields)
                if isfield(pair, numeric_fields{k})
                    row.([prefix numeric_fields{k}]) = double(pair.(numeric_fields{k}));
                end
            end
        end
    end
end

function labels = current_canonical_labels(~)
% CURRENT_CANONICAL_LABELS Perform the current canonical labels operation.
%
% Syntax:
%   labels = current_canonical_labels(~)
%
% Inputs:
%   ~ - Unused positional input.
%
% Outputs:
%   labels - Output text or identifier.

    labels = canonical_label_names();
end

function row = add_respiratory_reference_summary(row, resp_ref)
% ADD_RESPIRATORY_REFERENCE_SUMMARY Add respiratory reference summary.
%
% Syntax:
%   row = add_respiratory_reference_summary(row, resp_ref)
%
% Inputs:
%   row - Input value `row`.
%   resp_ref - Respiratory-reference structure.
%
% Outputs:
%   row - Computed output value `row`.

    row = add_belt_reference_fields(row, resp_ref, 'lungs');
    row = add_belt_reference_fields(row, resp_ref, 'diaph');

    row.change_pattern = '';
    if isstruct(resp_ref) && isfield(resp_ref, 'change_pattern')
        row.change_pattern = char(string(resp_ref.change_pattern));
    end
end

function row = add_belt_reference_fields(row, resp_ref, belt_name)
% ADD_BELT_REFERENCE_FIELDS Add belt reference fields.
%
% Syntax:
%   row = add_belt_reference_fields(row, resp_ref, belt_name)
%
% Inputs:
%   row - Input value `row`.
%   resp_ref - Respiratory-reference structure.
%   belt_name - Input value `belt_name`.
%
% Outputs:
%   row - Computed output value `row`.

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
% WRITE_MEASURE_COMPARABILITY_TABLE Write measure comparability table.
%
% Syntax:
%   out_csv = write_measure_comparability_table(out_dir)
%
% Inputs:
%   out_dir - File or dataset path.
%
% Outputs:
%   out_csv - Computed output value `out_csv`.

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
% GET_STRUCT_VALUE Return struct value.
%
% Syntax:
%   value = get_struct_value(s, name, default_value)
%
% Inputs:
%   s - Input value `s`.
%   name - Input value `name`.
%   default_value - Input value `default_value`.
%
% Outputs:
%   value - Computed numeric value.

    value = default_value;
    if isfield(s, name)
        value = s.(name);
    end
end

function value = get_loaded_value(loaded, field_name, default_value)
% GET_LOADED_VALUE Return loaded value.
%
% Syntax:
%   value = get_loaded_value(loaded, field_name, default_value)
%
% Inputs:
%   loaded - Input value `loaded`.
%   field_name - Input value `field_name`.
%   default_value - Input value `default_value`.
%
% Outputs:
%   value - Computed numeric value.

    if isfield(loaded, field_name)
        value = loaded.(field_name);
    else
        value = default_value;
    end
end

function fs = get_results_fs(loaded, config)
% GET_RESULTS_FS Return results fs.
%
% Syntax:
%   fs = get_results_fs(loaded, config)
%
% Inputs:
%   loaded - Input value `loaded`.
%   config - Pipeline configuration structure.
%
% Outputs:
%   fs - Computed output value `fs`.

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
% ADD_EVENT_COUNTS Add event counts.
%
% Syntax:
%   row = add_event_counts(row, events, canonical_labels)
%
% Inputs:
%   row - Input value `row`.
%   events - Event structure data.
%   canonical_labels - Label identifier or label metadata.
%
% Outputs:
%   row - Computed output value `row`.

    event_types = {};
    if ~isempty(events) && isfield(events, 'type')
        event_types = canonicalize_label_names({events.type});
    end
    labels = canonical_labels;
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
% ADD_DIAGNOSTIC_SUMMARIES Add diagnostic summaries.
%
% Syntax:
%   row = add_diagnostic_summaries(row, diagnostic_signals)
%
% Inputs:
%   row - Input value `row`.
%   diagnostic_signals - Detector diagnostic data.
%
% Outputs:
%   row - Computed output value `row`.

    row = add_numeric_struct_summaries(row, diagnostic_signals, ...
        'diagnostic', {'time_sec'});
end

function row = add_numeric_struct_summaries(row, source, prefix, skip_names)
% ADD_NUMERIC_STRUCT_SUMMARIES Add numeric struct summaries.
%
% Syntax:
%   row = add_numeric_struct_summaries(row, source, prefix, skip_names)
%
% Inputs:
%   row - Input value `row`.
%   source - Input value `source`.
%   prefix - Input value `prefix`.
%   skip_names - Input value `skip_names`.
%
% Outputs:
%   row - Computed output value `row`.

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
% FILL_MISSING_FIELDS Perform the fill missing fields operation.
%
% Syntax:
%   rows = fill_missing_fields(rows, all_fields)
%
% Inputs:
%   rows - Input value `rows`.
%   all_fields - Input value `all_fields`.
%
% Outputs:
%   rows - Computed output value `rows`.

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
% MISSING_VALUE_FOR_FIELD Perform the missing value for field operation.
%
% Syntax:
%   value = missing_value_for_field(name)
%
% Inputs:
%   name - Input value `name`.
%
% Outputs:
%   value - Computed numeric value.

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
% FILTER_RESULT_FILES Filter result files.
%
% Syntax:
%   files = filter_result_files(files, config)
%
% Inputs:
%   files - Input value `files`.
%   config - Pipeline configuration structure.
%
% Outputs:
%   files - Computed output value `files`.

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
% GET_GROUP_FILTER Return group filter.
%
% Syntax:
%   value = get_group_filter(config, name)
%
% Inputs:
%   config - Pipeline configuration structure.
%   name - Input value `name`.
%
% Outputs:
%   value - Computed numeric value.

    value = [];
    if isfield(config, 'group') && isfield(config.group, name)
        value = config.group.(name);
    elseif isfield(config, name)
        value = config.(name);
    end
    value = value(:)';
end

function group_name = subject_group_for_subject(subject, config)
% SUBJECT_GROUP_FOR_SUBJECT Perform the subject group for subject operation.
%
% Syntax:
%   group_name = subject_group_for_subject(subject, config)
%
% Inputs:
%   subject - Subject identifier.
%   config - Pipeline configuration structure.
%
% Outputs:
%   group_name - Output text or identifier.

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
% GET_SUBJECT_GROUP_LIST Return subject group list.
%
% Syntax:
%   subjects = get_subject_group_list(config, name)
%
% Inputs:
%   config - Pipeline configuration structure.
%   name - Input value `name`.
%
% Outputs:
%   subjects - Computed output value `subjects`.

    subjects = [];
    if isfield(config, 'group') && isfield(config.group, name)
        subjects = config.group.(name);
    elseif isfield(config, name)
        subjects = config.(name);
    end
    subjects = subjects(:)';
end

function [subject, measure] = parse_subject_measure(label_file)
% PARSE_SUBJECT_MEASURE Parse subject measure.
%
% Syntax:
%   [subject, measure] = parse_subject_measure(label_file)
%
% Inputs:
%   label_file - File or dataset path.
%
% Outputs:
%   subject - Computed output value `subject`.
%   measure - Computed output value `measure`.

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

function event_table = build_group_event_duration_table(files)
% BUILD_GROUP_EVENT_DURATION_TABLE Build group event duration table.
%
% Syntax:
%   event_table = build_group_event_duration_table(files)
%
% Inputs:
%   files - Input value `files`.
%
% Outputs:
%   event_table - Output table.

    subject = zeros(0,1);
    measurement = zeros(0,1);
    provenance = strings(0,1);
    label = strings(0,1);
    duration_sec = zeros(0,1);
    for i = 1:numel(files)
        filename = fullfile(files(i).folder, files(i).name);
        loaded = load(filename);
        fs = get_results_fs(loaded, struct());
        [file_subject, file_measure] = parse_subject_measure(filename);
        layers = {'automatic','reviewed'};
        event_fields = {'events_automatic','events_reviewed'};
        for j = 1:numel(layers)
            events = get_saved_events(loaded,event_fields{j});
            for k = 1:numel(events)
                if ~isfield(events,'type')
                    continue;
                end
                event_duration = authoritative_event_duration(events(k), fs);
                if ~isfinite(event_duration), continue; end
                subject(end+1,1) = get_loaded_value(loaded,'subject',file_subject); %#ok<AGROW>
                measurement(end+1,1) = get_loaded_value(loaded,'measure',file_measure); %#ok<AGROW>
                provenance(end+1,1) = string(layers{j}); %#ok<AGROW>
                mapped_label = canonicalize_label_names({events(k).type});
                label(end+1,1) = string(mapped_label{1}); %#ok<AGROW>
                duration_sec(end+1,1) = event_duration; %#ok<AGROW>
            end
        end
    end
    event_table = table(subject,measurement,provenance,label,duration_sec);
end

function duration = authoritative_event_duration(event, fs)
% AUTHORITATIVE_EVENT_DURATION Perform the authoritative event duration operation.
%
% Syntax:
%   duration = authoritative_event_duration(event, fs)
%
% Inputs:
%   event - Event structure data.
%   fs - Sampling frequency in hertz.
%
% Outputs:
%   duration - Computed numeric value.

    duration = NaN;
    if isfield(event, 'start_idx') && isfield(event, 'end_idx') && ...
            isnumeric(event.start_idx) && isnumeric(event.end_idx) && ...
            isscalar(event.start_idx) && isscalar(event.end_idx) && ...
            isfinite(event.start_idx) && isfinite(event.end_idx) && ...
            event.end_idx >= event.start_idx && isfinite(fs) && fs > 0
        duration = (round(event.end_idx) - round(event.start_idx) + 1) / fs;
    elseif isfield(event, 'duration') && isnumeric(event.duration) && ...
            isscalar(event.duration) && isfinite(event.duration)
        duration = event.duration;
    end
end

function boundary_table = build_group_boundary_qc_table(files)
% BUILD_GROUP_BOUNDARY_QC_TABLE Build group boundary qc table.
%
% Syntax:
%   boundary_table = build_group_boundary_qc_table(files)
%
% Inputs:
%   files - Input value `files`.
%
% Outputs:
%   boundary_table - Event-boundary provenance structure.

    subject = zeros(0,1);
    measurement = zeros(0,1);
    label = strings(0,1);
    belt = strings(0,1);
    candidate_start_t = zeros(0,1);
    candidate_end_t = zeros(0,1);
    localized_start_t = zeros(0,1);
    localized_end_t = zeros(0,1);
    localized_duration_sec = zeros(0,1);
    final_min_duration_sec = zeros(0,1);
    passes_final_min_duration = false(0,1);
    duration_shortfall_sec = zeros(0,1);
    rejection_reason = strings(0,1);
    evidence_source = strings(0,1);
    uncertainty_sec = zeros(0,1);

    for file_index = 1:numel(files)
        filename = fullfile(files(file_index).folder, files(file_index).name);
        loaded = load(filename);
        if ~isfield(loaded, 'event_boundary_info') || ...
                ~isstruct(loaded.event_boundary_info)
            continue;
        end
        [file_subject, file_measure] = parse_subject_measure(filename);
        boundary_fields = setdiff(fieldnames(loaded.event_boundary_info), {'version'});
        for field_index = 1:numel(boundary_fields)
            info = loaded.event_boundary_info.(boundary_fields{field_index});
            if ~isstruct(info) || ~isfield(info, 'events') || isempty(info.events)
                continue;
            end
            records = info.events;
            for record_index = 1:numel(records)
                record = records(record_index);
                minimum = numeric_record_field(record, 'final_min_duration_sec', NaN);
                if ~isfinite(minimum)
                    continue;
                end
                duration = numeric_record_field(record, 'localized_duration_sec', NaN);
                passed = logical(numeric_record_field( ...
                    record, 'passes_final_min_duration', false));
                record_label = text_record_field(record, 'label', boundary_fields{field_index});
                mapped_label = canonicalize_label_names({record_label});
                subject(end+1,1) = get_loaded_value(loaded, 'subject', file_subject); %#ok<AGROW>
                measurement(end+1,1) = get_loaded_value(loaded, 'measure', file_measure); %#ok<AGROW>
                label(end+1,1) = string(mapped_label{1}); %#ok<AGROW>
                belt(end+1,1) = string(text_record_field(record, 'belt', '')); %#ok<AGROW>
                candidate_start_t(end+1,1) = numeric_record_field(record, 'candidate_start_t', NaN); %#ok<AGROW>
                candidate_end_t(end+1,1) = numeric_record_field(record, 'candidate_end_t', NaN); %#ok<AGROW>
                localized_start_t(end+1,1) = numeric_record_field(record, 'localized_start_t', NaN); %#ok<AGROW>
                localized_end_t(end+1,1) = numeric_record_field(record, 'localized_end_t', NaN); %#ok<AGROW>
                localized_duration_sec(end+1,1) = duration; %#ok<AGROW>
                final_min_duration_sec(end+1,1) = minimum; %#ok<AGROW>
                passes_final_min_duration(end+1,1) = passed; %#ok<AGROW>
                duration_shortfall_sec(end+1,1) = max(0, minimum - duration); %#ok<AGROW>
                rejection_reason(end+1,1) = string(text_record_field(record, 'rejection_reason', '')); %#ok<AGROW>
                evidence_source(end+1,1) = string(text_record_field(record, 'evidence_source', '')); %#ok<AGROW>
                uncertainty_sec(end+1,1) = numeric_record_field(record, 'uncertainty_sec', NaN); %#ok<AGROW>
            end
        end
    end
    boundary_table = table(subject, measurement, label, belt, ...
        candidate_start_t, candidate_end_t, localized_start_t, localized_end_t, ...
        localized_duration_sec, final_min_duration_sec, ...
        passes_final_min_duration, duration_shortfall_sec, rejection_reason, ...
        evidence_source, uncertainty_sec);
end

function value = numeric_record_field(record, name, default_value)
% NUMERIC_RECORD_FIELD Perform the numeric record field operation.
%
% Syntax:
%   value = numeric_record_field(record, name, default_value)
%
% Inputs:
%   record - Input value `record`.
%   name - Input value `name`.
%   default_value - Input value `default_value`.
%
% Outputs:
%   value - Computed numeric value.

    value = default_value;
    if isfield(record, name) && isnumeric(record.(name)) && ...
            isscalar(record.(name)) && isfinite(record.(name))
        value = record.(name);
    elseif isfield(record, name) && islogical(record.(name)) && ...
            isscalar(record.(name))
        value = record.(name);
    end
end

function value = text_record_field(record, name, default_value)
% TEXT_RECORD_FIELD Perform the text record field operation.
%
% Syntax:
%   value = text_record_field(record, name, default_value)
%
% Inputs:
%   record - Input value `record`.
%   name - Input value `name`.
%   default_value - Input value `default_value`.
%
% Outputs:
%   value - Computed numeric value.

    value = default_value;
    if isfield(record, name) && ~isempty(record.(name))
        value = char(string(record.(name)));
    end
end
