function group_table = build_group_label_table(config_or_results_path)
% BUILD_GROUP_LABEL_TABLE Aggregate recording result files for cohort analysis.
%
% Inputs:
%   config_or_results_path - Configuration structure or results-directory path.
%
% Outputs:
%   group_table - One row per recording. Columns include file/subject/measure/group,
%                 recording duration, per-label availability/burden/event/review
%                 summaries, belt/reference QC, overlap, and numeric detector
%                 summaries. Dynamic per-label fields use canonical short names.
% Also writes group_label_summary CSV/MAT, measure-comparability metadata,
% per-event durations, compact candidate-event QC, and cohort QC summaries.

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
    candidate_event_qc = build_group_candidate_event_table(files);
    cohort_qc = build_cohort_qc_summary( ...
        group_table, canonical_labels, event_duration_table, candidate_event_qc);
    save(fullfile(out_dir, 'cohort_qc_summary.mat'), 'cohort_qc');
    if ~isempty(cohort_qc.by_label)
        writetable(cohort_qc.by_label, ...
            fullfile(out_dir, 'cohort_label_qc_summary.csv'));
    end
    writetable(event_duration_table, ...
        fullfile(out_dir, 'cohort_event_durations.csv'));
    writetable(candidate_event_qc, ...
        fullfile(out_dir, 'cohort_candidate_events.csv'));
    log_message(config, 1, 'Saved group label summary: %s', out_csv);
end

function row = label_file_to_summary_row(label_file, config, canonical_labels)
% LABEL_FILE_TO_SUMMARY_ROW Convert one saved recording into scalar table fields.
% label_file supplies saved results; config supplies grouping/fallback settings;
% canonical_labels fixes the label-summary column order and names.

    loaded = load(label_file);

    row = struct();
    row.label_file = label_file;
    [file_subject, file_measure] = parse_subject_measure(label_file);
    row.subject = get_loaded_value(loaded, 'subject', file_subject);
    row.measure = get_loaded_value(loaded, 'measure', file_measure);
    row.measurement = row.measure;
    row.subject_group = subject_group_for_subject(row.subject, config);
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

    if isfield(loaded, 'label_evidence_summary_automatic')
        row = add_compact_evidence_summaries( ...
            row, loaded.label_evidence_summary_automatic, ...
            'evidence_automatic');
    end
    if isfield(loaded, 'label_evidence_summary_reviewed')
        row = add_compact_evidence_summaries( ...
            row, loaded.label_evidence_summary_reviewed, ...
            'evidence_reviewed');
    end
    row = add_authoritative_trace_summaries(row, loaded);

end

function row = add_label_summaries(row, loaded, config, canonical_labels)
% ADD_LABEL_SUMMARIES Add label summaries.
% For each canonical label, adds availability, automatic positive duration
% in seconds, and fraction of assessable samples; duration_sec is recording length.

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
% Adds per-label automatic/reviewed event counts, automatic event-duration
% quantiles (seconds), reviewed coverage/burden, and automatic-versus-reviewed
% disagreement restricted to explicitly reviewed, assessable samples.

    saved_labels = canonical_labels;
    if isfield(loaded, 'label_names')
        saved_labels = canonicalize_label_names(loaded.label_names);
    end
    available = saved_label_availability(loaded, saved_labels);
    automatic_mask = get_saved_mask(loaded, 'mask_automatic');
    reviewed_mask = get_saved_mask(loaded, 'mask_reviewed');
    review_mask = get_saved_mask(loaded, 'review_coverage_mask');
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
% SAVED_LABEL_AVAILABILITY Resolve one availability flag per saved label.
% Uses explicit label_available when aligned, then the resolved nested input
% configuration. A top-level input_config branch reads older result files only.

    available = true(1, numel(saved_labels));
    if isfield(loaded, 'label_available') && ...
            (isnumeric(loaded.label_available) || islogical(loaded.label_available)) && ...
            numel(loaded.label_available) == numel(saved_labels)
        available = logical(loaded.label_available(:)');
    elseif isfield(loaded, 'config') && isstruct(loaded.config) && ...
            isfield(loaded.config, 'input_config') && ...
            isstruct(loaded.config.input_config) && ...
            isfield(loaded.config.input_config, 'running_labels')
        running_labels = canonicalize_label_names( ...
            loaded.config.input_config.running_labels);
        available = ismember(saved_labels, running_labels);
    elseif isfield(loaded, 'input_config') && isstruct(loaded.input_config) && ...
            isfield(loaded.input_config, 'running_labels')
        running_labels = canonicalize_label_names(loaded.input_config.running_labels);
        available = ismember(saved_labels, running_labels);
    end
end

function mask = get_saved_mask(loaded, field)
% GET_SAVED_MASK Return saved mask.
% Returns the numeric/logical sample x label array stored at field, or empty.

    mask = [];
    if isfield(loaded, field) && ...
            (isnumeric(loaded.(field)) || islogical(loaded.(field)))
        mask = loaded.(field);
    end
end

function assessable = saved_assessable_column(loaded, N, L, idx, available)
% SAVED_ASSESSABLE_COLUMN Return one sample-level label assessability vector.
% Uses column idx of an aligned Nsample x L saved mask; otherwise repeats the
% recording-level availability flag across N samples.

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
% Returns a stored event struct array or the canonical empty-event value.

    events = empty_events();
    if isfield(loaded, field) && isstruct(loaded.(field))
        events = loaded.(field);
    end
end

function count = count_events(events, label)
% COUNT_EVENTS Count events matching one canonicalized label type.

    count = 0;
    if ~isempty(events) && isfield(events, 'type')
        count = nnz(strcmp(canonicalize_label_names({events.type}), label));
    end
end

function durations = event_durations(events, label, fs)
% EVENT_DURATIONS Return finite durations in seconds for one canonical label.
% Sample indices and fs are authoritative when available; saved duration is fallback.

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
% Adds numeric lungs_belt_available/diaph_belt_available and categorical
% respiratory_belt_availability (two_belts, single_belt, or no_belt).

    lungs = false;
    diaph = false;
    if isfield(loaded, 'resp_features') && isstruct(loaded.resp_features) && ...
            isfield(loaded.resp_features, 'lungs') && ...
            isfield(loaded.resp_features, 'diaph')
        resp = loaded.resp_features;
    elseif isfield(loaded, 'phys_feat') && isstruct(loaded.phys_feat) && ...
            isfield(loaded.phys_feat, 'lungs') && ...
            isfield(loaded.phys_feat, 'diaph')
        resp = loaded.phys_feat;
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
% Flattens automatic/reviewed pair records into availability, overlap seconds,
% and directional overlap-fraction columns.

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
% CURRENT_CANONICAL_LABELS Return frozen short label names in mask-column order.

    labels = get_labels('short');
end

function row = add_respiratory_reference_summary(row, resp_ref)
% ADD_RESPIRATORY_REFERENCE_SUMMARY Add respiratory reference summary.
% Adds lung/diaphragm amplitude-reference fields and the cross-belt change pattern.

    row = add_belt_reference_fields(row, resp_ref, 'lungs');
    row = add_belt_reference_fields(row, resp_ref, 'diaph');

    row.change_pattern = '';
    if isstruct(resp_ref) && isfield(resp_ref, 'change_pattern')
        row.change_pattern = char(string(resp_ref.change_pattern));
    end
end

function row = add_belt_reference_fields(row, resp_ref, belt_name)
% ADD_BELT_REFERENCE_FIELDS Add belt reference fields.
% For one named belt, records early/late and change-point ratios/timing,
% session/global reference values in raw units, breath count, availability,
% global/session ratio, quality, and action. Missing evidence receives NaN/text defaults.

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
% Creates group_measure_comparability.csv with measure_family, comparability,
% units_or_scale, and interpretation columns distinguishing absolute measures,
% within-record normalized ratios, and uncalibrated raw belt amplitudes.

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
% Reads a named field from s, including empty values, or returns the fallback.

    value = default_value;
    if isfield(s, name)
        value = s.(name);
    end
end

function value = get_loaded_value(loaded, field_name, default_value)
% GET_LOADED_VALUE Return loaded value.
% Reads a variable from a loaded MAT-file struct or returns the fallback.

    if isfield(loaded, field_name)
        value = loaded.(field_name);
    else
        value = default_value;
    end
end

function fs = get_results_fs(loaded, config)
% GET_RESULTS_FS Return results fs.
% Prefers loaded.config.fs, then config.fs, with a 1-Hz legacy fallback.

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
% Adds events_<label>_count for available labels and NaN for unavailable labels.

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

function row = add_compact_evidence_summaries(row, evidence, prefix)
% ADD_COMPACT_EVIDENCE_SUMMARIES Flatten scalar ML-ready evidence only.

    row = add_scalar_summary_fields(row, evidence, prefix);
end

function row = add_scalar_summary_fields(row, source, prefix)
% ADD_SCALAR_SUMMARY_FIELDS Recursively retain scalar numeric/text summaries.

    names = fieldnames(source);
    skip = {'version', 'kind', 'available', 'availability_reason'};
    for i = 1:numel(names)
        name = names{i};
        if ismember(name, skip)
            continue;
        end
        value = source.(name);
        field = [prefix '_' matlab.lang.makeValidName(name)];
        if isstruct(value) && isscalar(value)
            row = add_scalar_summary_fields(row, value, field);
        elseif (isnumeric(value) || islogical(value)) && isscalar(value)
            row.(field) = double(value);
        end
    end
end

function row = add_authoritative_trace_summaries(row, loaded)
% ADD_AUTHORITATIVE_TRACE_SUMMARIES Summarize traces without a saved flat copy.

    mappings = { ...
        'resp_features', 'diaph.rate_slow_window_bpm', ...
            'trace_breathing_rate_slow_window_bpm_diaph'; ...
        'resp_features', 'diaph.irregularity.robust_cov', ...
            'trace_irregularity_robust_cov_diaph'; ...
        'detector_diagnostics', 'async.phase_coherence_mid', ...
            'trace_resp_asynchrony_phase_coherence_mid'; ...
        'resp_features', 'thoracoabdominal_balance.thoracic_to_abdominal_ratio', ...
            'trace_thoracic_to_abdominal_ratio'; ...
        'resp_features', 'thoracoabdominal_balance.thoracic_dominance_log_ratio', ...
            'trace_thoracic_dominance_log_ratio'; ...
        'resp_features', 'thoracoabdominal_balance.thoracic_relative_fraction', ...
            'trace_thoracic_relative_fraction'; ...
        'detector_diagnostics', 'periodic.eami.lungs.index', ...
            'trace_eami_lungs'};
    for i = 1:size(mappings, 1)
        if ~isfield(loaded, mappings{i, 1})
            continue;
        end
        value = nested_value(loaded.(mappings{i, 1}), mappings{i, 2});
        if isnumeric(value) || islogical(value)
            row = add_numeric_array_summary(row, value, mappings{i, 3});
        end
    end
end

function value = nested_value(source, path)
% NESTED_VALUE Resolve a dot-separated scalar-struct path.

    value = [];
    parts = strsplit(path, '.');
    for i = 1:numel(parts)
        if ~isstruct(source) || ~isscalar(source) || ...
                ~isfield(source, parts{i})
            return;
        end
        source = source.(parts{i});
    end
    value = source;
end

function row = add_numeric_array_summary(row, values, prefix)
% ADD_NUMERIC_ARRAY_SUMMARY Add finite distribution summaries for one trace.

    values = double(values(:));
    values = values(isfinite(values));
    if isempty(values)
        row.([prefix '_mean']) = NaN;
        row.([prefix '_median']) = NaN;
        row.([prefix '_p10']) = NaN;
        row.([prefix '_p90']) = NaN;
        row.([prefix '_std']) = NaN;
        row.([prefix '_cv']) = NaN;
        return;
    end
    row.([prefix '_mean']) = mean(values, 'omitnan');
    row.([prefix '_median']) = median(values, 'omitnan');
    row.([prefix '_p10']) = prctile(values, 10);
    row.([prefix '_p90']) = prctile(values, 90);
    row.([prefix '_std']) = std(values, 'omitnan');
    median_value = median(values, 'omitnan');
    if median_value ~= 0
        row.([prefix '_cv']) = row.([prefix '_std']) / abs(median_value);
    else
        row.([prefix '_cv']) = NaN;
    end
end

function rows = fill_missing_fields(rows, all_fields)
% FILL_MISSING_FIELDS Align scalar summary structs before table conversion.
% rows is a cell array; each output struct contains all_fields in identical order.

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
% MISSING_VALUE_FOR_FIELD Choose text, zero-availability, or NaN table defaults.

    if strcmp(name, 'label_file') || strcmp(name, 'subject_group') || ...
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
% Retains directory entries whose parsed subject/measurement match optional
% config.group filters (or legacy top-level filters).

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
% Returns the named group/top-level selector as a row vector.

    value = [];
    if isfield(config, 'group') && isfield(config.group, name)
        value = config.group.(name);
    elseif isfield(config, name)
        value = config.(name);
    end
    value = value(:)';
end

function group_name = subject_group_for_subject(subject, config)
% SUBJECT_GROUP_FOR_SUBJECT Classify a numeric subject as Control, Patient, or Unknown.

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
% Reads the named config.group or legacy top-level list as a row vector.

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
% Extracts numeric identifiers from a Sub<number>_M<number> filename/path;
% both outputs are NaN when the naming convention is absent.

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
% Returns one row per finite automatic/reviewed event with subject,
% measurement, provenance, canonical label, and duration_sec.

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
% AUTHORITATIVE_EVENT_DURATION Derive event seconds from inclusive sample indices.
% A finite saved duration is used only when valid indices/fs are unavailable.

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

function candidate_table = build_group_candidate_event_table(files)
% BUILD_GROUP_CANDIDATE_EVENT_TABLE Concatenate compact candidates by label.

    subject = zeros(0,1);
    measurement = zeros(0,1);
    label = strings(0,1);
    belt = strings(0,1);
    start_t = zeros(0,1);
    end_t = zeros(0,1);
    duration = zeros(0,1);
    accepted = false(0,1);
    rejection_reason = strings(0,1);
    uncertainty_sec = zeros(0,1);

    for file_index = 1:numel(files)
        filename = fullfile(files(file_index).folder, files(file_index).name);
        loaded = load(filename);
        if ~isfield(loaded, 'candidate_events') || ...
                ~isstruct(loaded.candidate_events)
            continue;
        end
        [file_subject, file_measure] = parse_subject_measure(filename);
        candidate_fields = fieldnames(loaded.candidate_events);
        for field_index = 1:numel(candidate_fields)
            records = loaded.candidate_events.(candidate_fields{field_index});
            if ~isstruct(records) || isempty(records)
                continue;
            end
            for record_index = 1:numel(records)
                record = records(record_index);
                record_label = candidate_fields{field_index};
                mapped_label = canonicalize_label_names({record_label});
                subject(end+1,1) = get_loaded_value(loaded, 'subject', file_subject); %#ok<AGROW>
                measurement(end+1,1) = get_loaded_value(loaded, 'measure', file_measure); %#ok<AGROW>
                label(end+1,1) = string(mapped_label{1}); %#ok<AGROW>
                belt(end+1,1) = string(text_record_field(record, 'belt', '')); %#ok<AGROW>
                start_t(end+1,1) = numeric_record_field(record, 'start_t', NaN); %#ok<AGROW>
                end_t(end+1,1) = numeric_record_field(record, 'end_t', NaN); %#ok<AGROW>
                duration(end+1,1) = numeric_record_field(record, 'duration', NaN); %#ok<AGROW>
                accepted(end+1,1) = logical(numeric_record_field( ...
                    record, 'accepted', false)); %#ok<AGROW>
                rejection_reason(end+1,1) = string(text_record_field(record, 'rejection_reason', '')); %#ok<AGROW>
                uncertainty_sec(end+1,1) = numeric_record_field(record, 'uncertainty_sec', NaN); %#ok<AGROW>
            end
        end
    end
    candidate_table = table(subject, measurement, label, belt, ...
        start_t, end_t, duration, accepted, rejection_reason, uncertainty_sec);
end

function value = numeric_record_field(record, name, default_value)
% NUMERIC_RECORD_FIELD Read a finite scalar numeric/logical record field or fallback.

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
% TEXT_RECORD_FIELD Convert a nonempty record field to text or return a fallback.

    value = default_value;
    if isfield(record, name) && ~isempty(record.(name))
        value = char(string(record.(name)));
    end
end
