function qc = build_cohort_qc_summary( ...
    group_table, label_names, event_duration_table, candidate_event_qc)
% BUILD_COHORT_QC_SUMMARY Aggregate per-recording label and candidate quality metrics.
%
% Inputs:
%   group_table          - One row per recording with generated label/QC columns.
%   label_names          - Canonical label names in output order.
%   event_duration_table - Optional one-row-per-event duration table (seconds).
%   candidate_event_qc   - Optional one-row-per-candidate-event QC table.
%
% Outputs:
%   qc - Scalar cohort_label_qc_v3 struct. Fields: version; n_recordings;
%        by_label table of assessability, event counts/fractions, review coverage,
%        disagreement, event-duration and rejected-candidate statistics;
%        original event_durations and candidate_events tables;
%        belt_availability counts; and reference_quality_warning_recordings.
%        phase_offset contains compact cohort summaries of the per-recording
%        descriptive polarity/phase QC exported through the group table.

    label_names = cellstr(string(label_names));
    if nargin < 3
        event_duration_table = table();
    end
    if nargin < 4
        candidate_event_qc = table();
    end
    qc = struct();
    qc.version = 'cohort_label_qc_v3';
    qc.n_recordings = height(group_table);
    qc.by_label = table();
    qc.event_durations = event_duration_table;
    qc.candidate_events = candidate_event_qc;
    qc.belt_availability = struct('two_belts', 0, 'single_belt', 0, 'no_belt', 0);
    qc.reference_quality_warning_recordings = 0;
    qc.phase_offset = empty_phase_offset_cohort_qc();
    if isempty(group_table)
        return;
    end

    n_labels = numel(label_names);
    assessable_recordings = zeros(n_labels, 1);
    automatic_event_count = zeros(n_labels, 1);
    automatic_fraction_mean = nan(n_labels, 1);
    automatic_fraction_median = nan(n_labels, 1);
    zero_event_recordings = zeros(n_labels, 1);
    reviewed_recordings = zeros(n_labels, 1);
    reviewed_coverage_mean = zeros(n_labels, 1);
    disagreement_mean = nan(n_labels, 1);
    event_duration_median_sec = nan(n_labels, 1);
    event_duration_p90_sec = nan(n_labels, 1);
    rejected_candidate_count = zeros(n_labels, 1);
    rejected_candidate_duration_median_sec = nan(n_labels, 1);
    rejected_candidate_duration_p90_sec = nan(n_labels, 1);
    rejected_candidate_duration_max_sec = nan(n_labels, 1);

    for i = 1:n_labels
        token = matlab.lang.makeValidName(label_names{i});
        available = numeric_column(group_table, ['label_' token '_available']);
        counts = numeric_column(group_table, ['events_' token '_automatic_count']);
        fractions = numeric_column(group_table, ['label_' token '_automatic_fraction']);
        coverage = numeric_column(group_table, ['label_' token '_reviewed_coverage_fraction']);
        disagreement = numeric_column(group_table, ...
            ['label_' token '_automatic_reviewed_disagreement_fraction']);
        duration_median = numeric_column(group_table, ...
            ['events_' token '_automatic_duration_median_sec']);
        duration_p90 = numeric_column(group_table, ...
            ['events_' token '_automatic_duration_p90_sec']);
        pooled_duration = pooled_automatic_duration(event_duration_table,label_names{i});
        rejected_duration = rejected_candidate_durations( ...
            candidate_event_qc, label_names{i});

        assessable_recordings(i) = nnz(available == 1);
        automatic_event_count(i) = sum(counts(isfinite(counts)), 'omitnan');
        automatic_fraction_mean(i) = finite_mean(fractions);
        automatic_fraction_median(i) = finite_median(fractions);
        zero_event_recordings(i) = nnz(available == 1 & counts == 0);
        reviewed_recordings(i) = nnz(coverage > 0);
        reviewed_coverage_mean(i) = finite_mean(coverage);
        disagreement_mean(i) = finite_mean(disagreement);
        if isempty(pooled_duration)
            event_duration_median_sec(i) = finite_median(duration_median);
            event_duration_p90_sec(i) = finite_median(duration_p90);
        else
            event_duration_median_sec(i) = median(pooled_duration,'omitnan');
            event_duration_p90_sec(i) = prctile(pooled_duration,90);
        end
        rejected_candidate_count(i) = numel(rejected_duration);
        rejected_candidate_duration_median_sec(i) = finite_median(rejected_duration);
        if ~isempty(rejected_duration)
            rejected_candidate_duration_p90_sec(i) = prctile(rejected_duration, 90);
            rejected_candidate_duration_max_sec(i) = max(rejected_duration);
        end
    end
    label = string(label_names(:));
    qc.by_label = table(label, assessable_recordings, automatic_event_count, ...
        automatic_fraction_mean, automatic_fraction_median, zero_event_recordings, ...
        reviewed_recordings, reviewed_coverage_mean, disagreement_mean, ...
        event_duration_median_sec, event_duration_p90_sec, ...
        rejected_candidate_count, rejected_candidate_duration_median_sec, ...
        rejected_candidate_duration_p90_sec, rejected_candidate_duration_max_sec);

    if ismember('respiratory_belt_availability', group_table.Properties.VariableNames)
        values = string(group_table.respiratory_belt_availability);
        qc.belt_availability.two_belts = nnz(values == "two_belts");
        qc.belt_availability.single_belt = nnz(values == "single_belt");
        qc.belt_availability.no_belt = nnz(values == "no_belt");
    end
    warning_mask = false(height(group_table), 1);
    for field = {'lungs_reference_quality', 'diaph_reference_quality'}
        if ismember(field{1}, group_table.Properties.VariableNames)
            quality = string(group_table.(field{1}));
            warning_mask = warning_mask | ...
                (~ismissing(quality) & quality ~= "" & quality ~= "good" & ...
                 quality ~= "belt_unavailable");
        end
    end
    qc.reference_quality_warning_recordings = nnz(warning_mask);
    qc.phase_offset = summarize_phase_offset_qc(group_table);
end

function summary = summarize_phase_offset_qc(group_table)
% SUMMARIZE_PHASE_OFFSET_QC Aggregate recording-level phase/polarity QC.

    summary = empty_phase_offset_cohort_qc();
    prefix = 'evidence_automatic_async_phase_offset_qc_';
    absolute = numeric_column(group_table, [prefix 'median_abs_phase_deg']);
    signed = numeric_column(group_table, [prefix 'median_signed_phase_deg']);
    resultant = numeric_column(group_table, [prefix 'median_resultant_length']);
    near_zero = numeric_column(group_table, ...
        [prefix 'fraction_reliable_near_0deg']);
    near_180 = numeric_column(group_table, ...
        [prefix 'fraction_reliable_near_180deg']);
    frequency_consistent = numeric_column(group_table, ...
        [prefix 'fraction_frequency_consistent_with_breath_timing']);
    lungs_multiplier = numeric_column(group_table, ...
        'evidence_automatic_async_lungs_polarity_multiplier');
    diaph_multiplier = numeric_column(group_table, ...
        'evidence_automatic_async_diaph_polarity_multiplier');

    summary.n_recordings_with_reliable_phase = nnz(isfinite(absolute));
    summary.median_recording_abs_phase_deg = finite_median(absolute);
    summary.median_recording_signed_phase_deg = finite_median(signed);
    summary.median_recording_resultant_length = finite_median(resultant);
    summary.median_fraction_reliable_near_0deg = finite_median(near_zero);
    summary.median_fraction_reliable_near_180deg = finite_median(near_180);
    summary.median_fraction_frequency_consistent_with_breath_timing = ...
        finite_median(frequency_consistent);
    configured = isfinite(lungs_multiplier) & isfinite(diaph_multiplier);
    summary.fixed_polarity_correction_recordings = nnz(configured & ...
        (lungs_multiplier ~= 1 | diaph_multiplier ~= 1));
end

function summary = empty_phase_offset_cohort_qc()
% EMPTY_PHASE_OFFSET_COHORT_QC Return stable compact cohort-QC fields.

    summary = struct( ...
        'n_recordings_with_reliable_phase', 0, ...
        'median_recording_abs_phase_deg', NaN, ...
        'median_recording_signed_phase_deg', NaN, ...
        'median_recording_resultant_length', NaN, ...
        'median_fraction_reliable_near_0deg', NaN, ...
        'median_fraction_reliable_near_180deg', NaN, ...
        'median_fraction_frequency_consistent_with_breath_timing', NaN, ...
        'fixed_polarity_correction_recordings', 0);
end

function durations = rejected_candidate_durations(T, label_name)
% REJECTED_CANDIDATE_DURATIONS Select finite rejected candidate durations.

    durations = [];
    required = {'label', 'duration', 'accepted'};
    if isempty(T) || ~all(ismember(required, T.Properties.VariableNames))
        return;
    end
    keep = string(T.label) == string(label_name) & ...
        ~logical(T.accepted);
    durations = double(T.duration(keep));
    durations = durations(isfinite(durations));
end

function values = pooled_automatic_duration(T, label_name)
% POOLED_AUTOMATIC_DURATION Return pooled automatic-event durations.
% Selects finite duration_sec values where provenance is automatic and the
% canonical label matches label_name.

    values = [];
    required = {'provenance','label','duration_sec'};
    if isempty(T) || ~all(ismember(required,T.Properties.VariableNames))
        return;
    end
    keep = string(T.provenance) == "automatic" & string(T.label) == string(label_name);
    values = double(T.duration_sec(keep));
    values = values(isfinite(values));
end

function values = numeric_column(T, name)
% NUMERIC_COLUMN Read a table variable as doubles or return one NaN per row.

    values = nan(height(T), 1);
    if ismember(name, T.Properties.VariableNames) && isnumeric(T.(name))
        values = double(T.(name));
    end
end

function value = finite_mean(values)
% FINITE_MEAN Average finite values, returning NaN for an empty selection.

    values = values(isfinite(values));
    if isempty(values), value = NaN; else, value = mean(values); end
end

function value = finite_median(values)
% FINITE_MEDIAN Take the median of finite values, or NaN when none exist.

    values = values(isfinite(values));
    if isempty(values), value = NaN; else, value = median(values); end
end
