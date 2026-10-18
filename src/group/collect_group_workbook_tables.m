function books = collect_group_workbook_tables(group_table, cohort, data)
% COLLECT_GROUP_WORKBOOK_TABLES Group related tables without changing values.
% Each row specifies a worksheet name, MATLAB table, and index description.
    phenotypes = cohort.phenotypes;
    automatic = addvars(phenotypes.summary_automatic, ...
        repmat("automatic", height(group_table), 1), ...
        'Before', 1, 'NewVariableNames', 'annotation_layer');
    reviewed = addvars(phenotypes.summary_reviewed, ...
        repmat("reviewed", height(group_table), 1), ...
        'Before', 1, 'NewVariableNames', 'annotation_layer');
    books.summary = {
        'Label_burden', label_burden_table(group_table), ...
            'One recording and label per row. Burdens and review coverage are fractions (0 to 1).';
        'Phenotypes', [automatic; reviewed], ...
            '24 raw features per recording. Automatic and reviewed rows are identified separately.'};
    books.details = {
        'Recordings', group_table, 'Full recording summaries, including detector and reference QC.';
        'Cohort_label_QC', cohort.qc.by_label, 'Cohort event and candidate QC by label.';
        'Event_durations', cohort.event_durations, 'One accepted label event per row, with duration in seconds.';
        'Candidate_events', cohort.candidate_events, 'Candidate events, acceptance flags, and rejection reasons.';
        'Phenotype_QC', phenotypes.long, 'Feature values, availability, coverage, and missing reasons for both layers.';
        'Feature_dictionary', phenotypes.dictionary, 'Feature names, units, roles, and source definitions.';
        'Measure_comparability', cohort.measure_comparability, 'Interpretation of absolute and within-record normalized measures.'};
    if nargin < 3, return; end
    labels = addvars(data.label_summary, ...
        repmat("label", height(data.label_summary), 1), ...
        'Before', 1, 'NewVariableNames', 'variable_type');
    features = addvars(data.feature_summary, ...
        repmat("phenotype_feature", height(data.feature_summary), 1), ...
        'Before', 1, 'NewVariableNames', 'variable_type');
    summary = addvars([labels; features], ...
        repmat(string(data.layer), height(labels)+height(features), 1), ...
        'Before', 1, 'NewVariableNames', 'annotation_layer');
    pairs = [data.label_pair_summary; data.feature_pair_summary];
    pairs = addvars(pairs, repmat(string(data.layer), height(pairs), 1), ...
        repmat(data.pair(1), height(pairs), 1), ...
        repmat(data.pair(2), height(pairs), 1), 'Before', 1, ...
        'NewVariableNames', {'annotation_layer', 'measurement_1', 'measurement_2'});
    books.summary = [books.summary; {
        'Descriptive', summary, 'By-measurement sample count, median, IQR, and quantiles in the stated units.';
        'Paired_summary', pairs, 'My minus Mx. Label changes use percentage points; feature changes retain their units.'}];
    changes = [data.label_pairs; data.feature_pairs];
    changes = addvars(changes, repmat(string(data.layer), height(changes), 1), ...
        'Before', 1, 'NewVariableNames', 'annotation_layer');
    books.details = [books.details; {
        'Paired_changes', changes, 'Subject-matched raw values, availability, changes, and valid-pair flags.';
        'Subject_groups', data.group_mapping, 'Control, Patient, or Unknown, with metadata provenance.'}];
    counts = table(); bins = table();
    if isfield(data, 'label_histograms')
        counts = data.label_histograms.counts;
        bins = data.label_histograms.bins;
    end
    if isfield(data, 'group_histograms')
        counts = [counts; data.group_histograms.counts];
        bins = [bins; data.group_histograms.bins];
    end
    if width(counts) > 0
        books.details = [books.details; {
            'Label_counts', counts, 'Assessable, zero, and positive counts by measurement, label, and cohort.';
            'Label_bins', bins, 'Exact 5-percentage-point histogram bins for All, Control, and Patient cohorts.'}];
    end
    if isfield(data, 'manifest')
        books.details(end+1, :) = {'Manifest', data.manifest, ...
            'Current generated outputs, cohort counts, annotation layer, and paired measurements.'};
    end
end

function T = label_burden_table(group_table)
    names = get_labels('short');
    n = height(group_table);
    T = table();
    if n == 0, return; end
    for l = 1:numel(names)
        label = repmat(string(names{l}), n, 1);
        stem = ['label_' names{l} '_'];
        available = column_or_nan(group_table, [stem 'available']);
        automatic_fraction = column_or_nan(group_table, [stem 'automatic_fraction']);
        reviewed_fraction = column_or_nan(group_table, [stem 'reviewed_fraction']);
        reviewed_coverage_fraction = column_or_nan(group_table, [stem 'reviewed_coverage_fraction']);
        event_count = column_or_nan(group_table, ['events_' names{l} '_count']);
        part = table(string(group_table.recording_id), group_table.subject, ...
            group_table.measure, string(group_table.subject_group), label, ...
            available, automatic_fraction, reviewed_fraction, ...
            reviewed_coverage_fraction, event_count, 'VariableNames', ...
            {'recording_id', 'subject', 'measure', 'subject_group', 'label', ...
            'available', 'automatic_fraction', 'reviewed_fraction', ...
            'reviewed_coverage_fraction', 'event_count'});
        T = [T; part]; %#ok<AGROW>
    end
    T = sortrows(T, {'subject', 'measure', 'label'});
end

function values = column_or_nan(T, name)
    values = nan(height(T), 1);
    if ismember(name, T.Properties.VariableNames), values = double(T.(name)); end
end
