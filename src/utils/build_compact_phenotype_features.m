function compact = build_compact_phenotype_features( ...
    label_burden, overlaps, label_evidence)
% BUILD_COMPACT_PHENOTYPE_FEATURES Build the fixed raw Level-2B representation.
% Inputs are the Level-1 burden/overlap/evidence summaries for one annotation
% layer. The 21 output values follow get_phenotype_feature_schema exactly.
% NaN is retained for unavailable or insufficiently supported evidence; no
% imputation, scaling, or cross-recording normalization occurs here.

    schema = get_phenotype_feature_schema();
    N = schema.n_features;
    values = nan(1, N);
    available = false(1, N);
    coverage = nan(1, N);
    missing_reason = repmat({'unavailable'}, 1, N);

    rapid = burden_entry(label_burden, 'rapid');
    deep = burden_entry(label_burden, 'deep');
    sigh = burden_entry(label_burden, 'sigh');
    irregular = burden_entry(label_burden, 'irregular');
    thoracic = burden_entry(label_burden, 'thoracic');
    async = burden_entry(label_burden, 'async');
    apnea = burden_entry(label_burden, 'apnea');
    periodic = burden_entry(label_burden, 'periodic');
    shallow = burden_entry(label_burden, 'shallow');
    slow = burden_entry(label_burden, 'slow');
    desat = burden_entry(label_burden, 'desat');
    rapid_deep = overlap_entry(overlaps, 'rapid_deep');
    sigh_irregular = overlap_entry(overlaps, 'sigh_irregular');

    set_burden(1, rapid);
    set_burden(2, deep);
    set_value(3, metric(rapid_deep, ...
        'overlap_fraction_of_joint_assessable'), ...
        metric(rapid_deep, 'available', false), ...
        overlap_coverage(rapid_deep, label_burden), ...
        'rapid_deep_overlap_unavailable');
    set_value(4, finite_median([ ...
        label_metric(label_evidence, 'rapid', 'recording_median_rr_lungs'), ...
        label_metric(label_evidence, 'rapid', 'recording_median_rr_diaph')]), ...
        rapid.available, burden_coverage(rapid, label_burden), ...
        label_reason(label_evidence, 'rapid', ...
            'no_finite_recording_scope_rate_evidence'));
    set_value(5, finite_median([ ...
        label_metric(label_evidence, 'deep', 'recording_median_ratio_lungs'), ...
        label_metric(label_evidence, 'deep', 'recording_median_ratio_diaph')]), ...
        deep.available, burden_coverage(deep, label_burden), ...
        label_reason(label_evidence, 'deep', ...
            'no_finite_recording_scope_excursion_evidence'));

    set_value(6, metric(label_burden, 'sighs_per_15_min'), sigh.available, ...
        burden_coverage(sigh, label_burden), ...
        label_reason(label_evidence, 'sigh', 'sigh_frequency_unavailable'));
    max_sigh_reason = metric(label_burden, ...
        'max_sighs_in_any_15_min_window_missing_reason', ...
        'insufficient_continuous_assessable_15_min_interval');
    set_value(7, metric(label_burden, ...
        'max_sighs_in_any_15_min_window'), sigh.available, ...
        burden_coverage(sigh, label_burden), max_sigh_reason);
    set_burden(8, irregular);
    set_value(9, metric(sigh_irregular, ...
        'fraction_of_a_events_with_b_at_midpoint'), ...
        metric(sigh_irregular, 'available', false), ...
        overlap_coverage(sigh_irregular, label_burden), ...
        'sigh_irregular_event_overlap_unavailable');
    set_value(10, finite_median([ ...
        label_metric(label_evidence, 'irregular', ...
            'recording_median_cov_lungs'), ...
        label_metric(label_evidence, 'irregular', ...
            'recording_median_cov_diaph')]), ...
        irregular.available, burden_coverage(irregular, label_burden), ...
        label_reason(label_evidence, 'irregular', ...
            'no_finite_recording_scope_ibi_cov_evidence'));

    set_burden(11, thoracic);
    set_value(12, label_metric(label_evidence, 'thoracic', ...
        'recording_median_thoracic_to_abdominal_ratio'), ...
        thoracic.available, burden_coverage(thoracic, label_burden), ...
        label_reason(label_evidence, 'thoracic', ...
            'no_finite_recording_scope_thoracoabdominal_balance_evidence'));
    set_event_duration(13, thoracic, label_evidence, 'thoracic');
    set_burden(14, async);
    set_value(15, label_metric(label_evidence, 'async', ...
        'recording_median_absolute_phase_deg'), ...
        async.available, burden_coverage(async, label_burden), ...
        label_reason(label_evidence, 'async', ...
            'no_finite_reliable_recording_scope_phase_evidence'));
    set_event_duration(16, async, label_evidence, 'async');

    set_burden(17, apnea);
    set_burden(18, periodic);
    set_burden(19, shallow);
    set_burden(20, slow);
    set_burden(21, desat);

    compact = struct( ...
        'version', 'magma_compact_phenotype_features_v1', ...
        'schema_version', schema.version, ...
        'n_features', schema.n_features, ...
        'feature_names', {schema.feature_names}, ...
        'values', double(values), ...
        'available', logical(available), ...
        'coverage_fraction', double(coverage), ...
        'missing_reason', {missing_reason}, ...
        'phenotype_group', {schema.phenotype_group}, ...
        'feature_role', {schema.feature_role}, ...
        'units', {schema.units});

    function set_burden(index, entry)
        set_value(index, entry.fraction, entry.available, ...
            burden_coverage(entry, label_burden), entry.missing_reason);
    end

    function set_event_duration(index, entry, evidence, label)
        value = entry.median_event_duration_sec;
        reason = entry.missing_reason;
        if entry.available && isfinite(entry.event_count) && entry.event_count == 0
            value = 0;
            reason = '';
        elseif entry.available && entry.event_count > 0 && ~isfinite(value)
            reason = 'insufficient_event_duration_support';
        elseif ~entry.available
            reason = label_reason(evidence, label, entry.missing_reason);
        end
        set_value(index, value, entry.available, ...
            burden_coverage(entry, label_burden), reason);
    end

    function set_value(index, value, source_available, source_coverage, reason)
        candidate = double_scalar(value);
        if logical(source_available) && isfinite(candidate)
            values(index) = candidate;
        else
            values(index) = NaN;
        end
        coverage(index) = double_scalar(source_coverage);
        available(index) = logical(source_available) && isfinite(values(index));
        if available(index)
            missing_reason{index} = '';
        else
            missing_reason{index} = normalize_reason(reason);
        end
    end
end

function entry = burden_entry(burden, name)
% BURDEN_ENTRY Read one burden entry with stable unavailable fallbacks.

    entry = struct('available', false, 'fraction', NaN, 'event_count', NaN, ...
        'assessable_duration_sec', NaN, 'median_event_duration_sec', NaN, ...
        'missing_reason', 'detector_unavailable');
    if isstruct(burden) && isfield(burden, 'by_label') && ...
            isfield(burden.by_label, name)
        source = burden.by_label.(name);
        fields = fieldnames(entry);
        for i = 1:numel(fields)
            if isfield(source, fields{i}) && ~isempty(source.(fields{i}))
                entry.(fields{i}) = source.(fields{i});
            end
        end
        if entry.available
            entry.missing_reason = 'available_but_value_undefined';
        end
    end
end

function out = overlap_entry(overlaps, name)
% OVERLAP_ENTRY Read one overlap entry without inventing availability.

    out = struct();
    if isstruct(overlaps) && isfield(overlaps, name)
        out = overlaps.(name);
    end
end

function coverage = burden_coverage(entry, burden)
% BURDEN_COVERAGE Express assessable duration as a fraction of recording time.

    coverage = NaN;
    duration = metric(burden, 'recording_duration_sec');
    if isfinite(duration) && duration > 0 && ...
            isfinite(entry.assessable_duration_sec)
        coverage = entry.assessable_duration_sec / duration;
    end
end

function coverage = overlap_coverage(entry, burden)
% OVERLAP_COVERAGE Express joint assessability as a recording fraction.

    coverage = NaN;
    duration = metric(burden, 'recording_duration_sec');
    joint = metric(entry, 'joint_assessable_duration_sec');
    if isfinite(duration) && duration > 0 && isfinite(joint)
        coverage = joint / duration;
    end
end

function value = label_metric(summary, label, field)
% LABEL_METRIC Read one evidence scalar or return NaN.

    value = NaN;
    if isstruct(summary) && isfield(summary, label)
        value = metric(summary.(label), field);
    end
end

function reason = label_reason(summary, label, fallback)
% LABEL_REASON Prefer the layer-specific detector availability explanation.

    reason = fallback;
    if isstruct(summary) && isfield(summary, label) && ...
            isfield(summary.(label), 'available') && ...
            ~logical(summary.(label).available)
        reason = metric(summary.(label), 'availability_reason', fallback);
    end
end

function value = metric(source, field, default_value)
% METRIC Read a present nonempty field with a stable fallback.

    if nargin < 3, default_value = NaN; end
    value = default_value;
    if isstruct(source) && isfield(source, field) && ~isempty(source.(field))
        value = source.(field);
    end
end

function value = finite_median(values)
% FINITE_MEDIAN Combine available belt-level recording medians.

    values = double(values(:));
    values = values(isfinite(values));
    if isempty(values), value = NaN; else, value = median(values); end
end

function value = double_scalar(value)
% DOUBLE_SCALAR Normalize numeric/logical scalars and reject other payloads.

    if (isnumeric(value) || islogical(value)) && isscalar(value)
        value = double(value);
    else
        value = NaN;
    end
end

function reason = normalize_reason(reason)
% NORMALIZE_REASON Return one nonempty aligned text reason.

    if isempty(reason)
        reason = 'unavailable_or_undefined';
    elseif iscell(reason)
        reason = reason{1};
    end
    reason = char(string(reason));
    if isempty(reason), reason = 'unavailable_or_undefined'; end
end
