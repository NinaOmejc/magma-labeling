function qc = build_cohort_qc_summary(group_table, label_names, event_duration_table)
% build_cohort_qc_summary
% Cohort-ready descriptive QC only. This function never tunes thresholds.

    label_names = cellstr(string(label_names));
    if nargin < 3
        event_duration_table = table();
    end
    qc = struct();
    qc.version = 'cohort_label_qc_v1';
    qc.n_recordings = height(group_table);
    qc.by_label = table();
    qc.event_durations = event_duration_table;
    qc.belt_availability = struct('two_belts', 0, 'single_belt', 0, 'no_belt', 0);
    qc.reference_quality_warning_recordings = 0;
    if isempty(group_table)
        return;
    end

    n_labels = numel(label_names);
    assessable_recordings = zeros(n_labels, 1);
    weak_event_count = zeros(n_labels, 1);
    weak_fraction_mean = nan(n_labels, 1);
    weak_fraction_median = nan(n_labels, 1);
    zero_event_recordings = zeros(n_labels, 1);
    reviewed_recordings = zeros(n_labels, 1);
    reviewed_coverage_mean = zeros(n_labels, 1);
    disagreement_mean = nan(n_labels, 1);
    event_duration_median_sec = nan(n_labels, 1);
    event_duration_p90_sec = nan(n_labels, 1);

    for i = 1:n_labels
        token = matlab.lang.makeValidName(label_names{i});
        available = numeric_column(group_table, ['label_' token '_available']);
        counts = numeric_column(group_table, ['events_' token '_weak_count']);
        fractions = numeric_column(group_table, ['label_' token '_weak_fraction']);
        coverage = numeric_column(group_table, ['label_' token '_reviewed_coverage_fraction']);
        disagreement = numeric_column(group_table, ...
            ['label_' token '_weak_reviewed_disagreement_fraction']);
        duration_median = numeric_column(group_table, ...
            ['events_' token '_weak_duration_median_sec']);
        duration_p90 = numeric_column(group_table, ...
            ['events_' token '_weak_duration_p90_sec']);
        pooled_duration = pooled_weak_duration(event_duration_table,label_names{i});

        assessable_recordings(i) = nnz(available == 1);
        weak_event_count(i) = sum(counts(isfinite(counts)), 'omitnan');
        weak_fraction_mean(i) = finite_mean(fractions);
        weak_fraction_median(i) = finite_median(fractions);
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
    end
    label = string(label_names(:));
    qc.by_label = table(label, assessable_recordings, weak_event_count, ...
        weak_fraction_mean, weak_fraction_median, zero_event_recordings, ...
        reviewed_recordings, reviewed_coverage_mean, disagreement_mean, ...
        event_duration_median_sec, event_duration_p90_sec);

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
end

function values = pooled_weak_duration(T, label_name)
    values = [];
    required = {'provenance','label','duration_sec'};
    if isempty(T) || ~all(ismember(required,T.Properties.VariableNames))
        return;
    end
    keep = string(T.provenance) == "weak" & string(T.label) == string(label_name);
    values = double(T.duration_sec(keep));
    values = values(isfinite(values));
end

function values = numeric_column(T, name)
    values = nan(height(T), 1);
    if ismember(name, T.Properties.VariableNames) && isnumeric(T.(name))
        values = double(T.(name));
    end
end

function value = finite_mean(values)
    values = values(isfinite(values));
    if isempty(values), value = NaN; else, value = mean(values); end
end

function value = finite_median(values)
    values = values(isfinite(values));
    if isempty(values), value = NaN; else, value = median(values); end
end
