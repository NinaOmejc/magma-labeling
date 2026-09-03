function export_results_hdf5(filename, results, signals_raw, signals_preprocessed)
% export_results_hdf5
% Write one flat, MATLAB-object-free HDF5 file for a subject x measurement.
% Numeric/logical values are datasets; text is UTF-8 encoded in zero-padded
% uint8 columns. Empty values are explicit scalar datasets with is_empty=1.

    filename = char(string(filename));
    validate_export_inputs(filename, results, signals_raw, signals_preprocessed);
    out_dir = fileparts(filename);
    if ~isempty(out_dir) && ~isfolder(out_dir)
        mkdir(out_dir);
    end
    if isfile(filename)
        delete(filename);
    end

    fs = results.config.fs;
    N = size(signals_preprocessed, 1);
    write_numeric(filename, '/signals/raw', signals_raw);
    write_numeric(filename, '/signals/preprocessed', signals_preprocessed);
    write_numeric(filename, '/time', (0:N-1)' / fs);

    write_resp_belt(filename, '/resp/lungs', results.resp_features.resp.lungs);
    write_resp_belt(filename, '/resp/diaph', results.resp_features.resp.diaph);
    write_value(filename, '/session_reference', results.session_reference);
    write_value(filename, '/resp_reference/lungs', results.resp_ref.lungs);
    write_value(filename, '/resp_reference/diaph', results.resp_ref.diaph);
    write_value(filename, '/spo2_reference', results.spo2_ref);
    write_value(filename, '/resp_features', results.resp_features);
    if isfield(results, 'diagnostic_signals')
        write_value(filename, '/resp_features/detector_signals', ...
            results.diagnostic_signals);
    end
    if isfield(results, 'detector_diagnostics')
        write_value(filename, '/resp_features/detector_diagnostics', ...
            results.detector_diagnostics);
    end

    write_text(filename, '/labels/names', results.label_names);
    write_numeric(filename, '/labels/available', uint8(results.label_available(:)'));
    write_text(filename, '/labels/availability_reason', results.label_availability_reason);
    write_numeric(filename, '/labels/assessable_mask', uint8(results.label_assessable_mask));
    write_numeric(filename, '/labels/weak_mask', uint8(results.mask_weak));
    write_numeric(filename, '/labels/reviewed_mask', uint8(results.mask_reviewed));
    write_numeric(filename, '/labels/review_mask', uint8(results.gold_review_mask));
    write_text(filename, '/labels/review_status', results.review_status);
    if isfield(results, 'label_reviewed_available')
        write_numeric(filename, '/labels/reviewed_available', ...
            uint8(results.label_reviewed_available(:)'));
    end
    if isfield(results, 'label_reviewed_availability_reason')
        write_text(filename, '/labels/reviewed_availability_reason', ...
            results.label_reviewed_availability_reason);
    end
    if isfield(results, 'label_reviewed_assessable_mask')
        write_numeric(filename, '/labels/reviewed_assessable_mask', ...
            uint8(results.label_reviewed_assessable_mask));
    end

    write_events(filename, '/events/weak', results.events_weak);
    write_events(filename, '/events/reviewed', results.events_reviewed);
    if isfield(results, 'event_boundary_info')
        write_value(filename, '/events/boundary_info', results.event_boundary_info);
    end

    write_value(filename, '/burden/weak', results.label_burden_weak);
    write_value(filename, '/burden/reviewed', results.label_burden_reviewed);
    write_value(filename, '/overlap/weak', results.label_overlap_summary_weak);
    write_value(filename, '/overlap/reviewed', results.label_overlap_summary_reviewed);
    write_value(filename, '/phenotype_evidence', results.db_phenotype_evidence);

    write_numeric(filename, '/meta/subject', results.subject);
    write_numeric(filename, '/meta/measurement', results.measure);
    write_numeric(filename, '/meta/fs', fs);
    write_text(filename, '/meta/label_schema_version', results.label_schema_version);
    write_text(filename, '/meta/resp_features_version', results.resp_features.version);
    write_text(filename, '/meta/annotation_schema_version', results.annotation_schema_version);
    write_text(filename, '/meta/export_schema_version', results.export_schema_version);
    write_text(filename, '/meta/upstream_input_preprocessing', ...
        results.upstream_input_preprocessing);
end

function validate_export_inputs(filename, results, raw, preprocessed)
    if isempty(filename)
        error('MAGMA:HDF5:InvalidFilename', 'A nonempty output filename is required.');
    end
    required = {'config', 'resp_features', 'session_reference', 'resp_ref', ...
        'spo2_ref', 'label_names', ...
        'label_available', 'label_availability_reason', 'label_assessable_mask', ...
        'mask_weak', 'mask_reviewed', 'gold_review_mask', 'review_status', ...
        'events_weak', 'events_reviewed', 'label_burden_weak', ...
        'label_burden_reviewed', 'label_overlap_summary_weak', ...
        'label_overlap_summary_reviewed', 'db_phenotype_evidence', ...
        'label_reviewed_available', 'label_reviewed_availability_reason', ...
        'label_reviewed_assessable_mask', 'label_schema_version', ...
        'annotation_schema_version', ...
        'export_schema_version', 'upstream_input_preprocessing', ...
        'subject', 'measure'};
    missing = required(~isfield(results, required));
    if ~isempty(missing)
        error('MAGMA:HDF5:MissingResultField', ...
            'Missing required result field(s): %s.', strjoin(missing, ', '));
    end
    if ~isnumeric(raw) || ~isnumeric(preprocessed) || ...
            size(raw, 1) ~= size(preprocessed, 1)
        error('MAGMA:HDF5:SignalAlignment', ...
            'Raw and preprocessed numeric signals must have equal row counts.');
    end
    N = size(preprocessed, 1);
    L = numel(results.label_names);
    expected = canonical_label_names();
    if ~isequal(cellstr(string(results.label_names)), expected)
        error('MAGMA:HDF5:LabelOrder', 'HDF5 export requires the frozen 11-label order.');
    end
    if ~strcmp(char(string(results.label_schema_version)), ...
            'independent_labels_v3_11class')
        error('MAGMA:HDF5:LabelSchemaVersion', ...
            'HDF5 export requires independent_labels_v3_11class.');
    end
    vector_fields = {'label_available', 'label_availability_reason', ...
        'label_reviewed_available', 'label_reviewed_availability_reason', ...
        'review_status'};
    for i = 1:numel(vector_fields)
        if numel(results.(vector_fields{i})) ~= L
            error('MAGMA:HDF5:LabelAlignment', ...
                '%s must contain one value per frozen label.', vector_fields{i});
        end
    end
    mask_fields = {'label_assessable_mask', 'label_reviewed_assessable_mask', ...
        'mask_weak', 'mask_reviewed', 'gold_review_mask'};
    for i = 1:numel(mask_fields)
        if ~isequal(size(results.(mask_fields{i})), [N L])
            error('MAGMA:HDF5:MaskAlignment', ...
                '%s must be N-by-11 and label aligned.', mask_fields{i});
        end
    end
    if ~isfield(results.config, 'fs') || ~isnumeric(results.config.fs) || ...
            ~isscalar(results.config.fs) || ~isfinite(results.config.fs) || ...
            results.config.fs <= 0
        error('MAGMA:HDF5:InvalidSamplingRate', ...
            'results.config.fs must be a finite positive scalar.');
    end
    validate_canonical_events(results.events_weak, results.config.fs, expected);
    validate_canonical_events(results.events_reviewed, results.config.fs, expected);
    validate_session_reference(results.session_reference, N, ...
        results.config.fs, results.measure);
end

function validate_session_reference(reference, N, fs, measurement)
    required = {'reference_start_idx', 'reference_end_idx', ...
        'reference_start_t', 'reference_end_t', 'reference_duration_sec', ...
        'protocol_phase', 'measurement', 'reference_schema_version', ...
        'available', 'complete', 'truncated', 'quality'};
    if ~isstruct(reference) || ~isscalar(reference) || ...
            ~all(isfield(reference, required))
        error('MAGMA:HDF5:SessionReferenceSchema', ...
            'Session-reference metadata are missing required fields.');
    end
    if ~strcmp(char(string(reference.reference_schema_version)), ...
            'session_physiological_reference_v1') || ...
            reference.measurement ~= measurement
        error('MAGMA:HDF5:SessionReferenceSchema', ...
            'Session-reference schema or measurement does not match the recording.');
    end
    if ~reference.available
        return;
    end
    start_idx = reference.reference_start_idx;
    end_idx = reference.reference_end_idx;
    expected_start_t = (start_idx - 1) / fs;
    expected_end_t = end_idx / fs;
    expected_duration = (end_idx - start_idx + 1) / fs;
    tolerance = 10 * eps(max(1, abs(expected_end_t)));
    if start_idx < 1 || end_idx < start_idx || end_idx > N || ...
            abs(reference.reference_start_t - expected_start_t) > tolerance || ...
            abs(reference.reference_end_t - expected_end_t) > tolerance || ...
            abs(reference.reference_duration_sec - expected_duration) > tolerance
        error('MAGMA:HDF5:SessionReferenceTiming', ...
            'Session-reference metadata must follow half-open index-derived timing.');
    end
end

function validate_canonical_events(events, fs, labels)
    required = {'type', 'start_idx', 'end_idx', 'start_t', 'end_t', ...
        'duration', 'belt'};
    if ~isstruct(events) || ~all(isfield(events, required))
        error('MAGMA:HDF5:EventSchema', ...
            'Exported events must use the canonical seven-field event schema.');
    end
    for i = 1:numel(events)
        if ~ismember(char(string(events(i).type)), labels)
            error('MAGMA:HDF5:EventType', ...
                'Exported event type "%s" is not canonical.', events(i).type);
        end
        start_idx = round(events(i).start_idx);
        end_idx = round(events(i).end_idx);
        expected_start_t = (start_idx - 1) / fs;
        expected_end_t = end_idx / fs;
        expected_duration = (end_idx - start_idx + 1) / fs;
        tolerance = 10 * eps(max(1, abs(expected_end_t)));
        if end_idx < start_idx || ...
                abs(events(i).start_t - expected_start_t) > tolerance || ...
                abs(events(i).end_t - expected_end_t) > tolerance || ...
                abs(events(i).duration - expected_duration) > tolerance
            error('MAGMA:HDF5:EventTiming', ...
                'Exported events must follow the half-open index-derived time convention.');
        end
    end
end

function write_resp_belt(filename, path, belt)
    fields = {'peak_idx', 'peak_t', 'amp', 'ibi', 'rr_bpm', ...
        'amp_ratio_session', 'amp_ratio_global'};
    for i = 1:numel(fields)
        value = [];
        if isfield(belt, fields{i}), value = belt.(fields{i}); end
        write_numeric(filename, [path '/' fields{i}], value);
    end
    if isfield(belt, 'available')
        write_numeric(filename, [path '/available'], uint8(belt.available));
    end
end

function write_events(filename, path, events)
    write_text(filename, [path '/type'], event_field(events, 'type', 'text'));
    write_numeric(filename, [path '/start_idx'], event_field(events, 'start_idx', 'numeric'));
    write_numeric(filename, [path '/end_idx'], event_field(events, 'end_idx', 'numeric'));
    write_numeric(filename, [path '/start_t'], event_field(events, 'start_t', 'numeric'));
    write_numeric(filename, [path '/end_t'], event_field(events, 'end_t', 'numeric'));
    write_numeric(filename, [path '/duration'], event_field(events, 'duration', 'numeric'));
    write_text(filename, [path '/belt'], event_field(events, 'belt', 'text'));
end

function values = event_field(events, name, kind)
    if isempty(events) || ~isfield(events, name)
        if strcmp(kind, 'text'), values = {}; else, values = []; end
    elseif strcmp(kind, 'text')
        values = {events.(name)};
    else
        values = [events.(name)]';
    end
end

function write_value(filename, path, value)
    if isstruct(value)
        if isempty(value)
            write_empty(filename, [path '/empty_struct']);
        elseif isscalar(value)
            names = fieldnames(value);
            for i = 1:numel(names)
                write_value(filename, [path '/' safe_name(names{i})], value.(names{i}));
            end
        else
            write_struct_array(filename, path, value);
        end
    elseif isnumeric(value) || islogical(value)
        write_numeric(filename, path, value);
    elseif ischar(value) || isstring(value)
        write_text(filename, path, value);
    elseif iscell(value)
        write_cell(filename, path, value);
    else
        error('MAGMA:HDF5:UnsupportedType', ...
            'Unsupported value at %s (%s).', path, class(value));
    end
end

function write_struct_array(filename, path, values)
    names = fieldnames(values);
    for i = 1:numel(names)
        parts = {values.(names{i})};
        if all(cellfun(@(x) isnumeric(x) && isscalar(x), parts))
            write_numeric(filename, [path '/' safe_name(names{i})], cell2mat(parts(:)));
        elseif all(cellfun(@(x) ischar(x) || (isstring(x) && isscalar(x)), parts))
            write_text(filename, [path '/' safe_name(names{i})], parts);
        else
            for j = 1:numel(values)
                item_path = sprintf('%s/item_%06d/%s', path, j, safe_name(names{i}));
                write_value(filename, item_path, values(j).(names{i}));
            end
        end
    end
end

function write_cell(filename, path, values)
    if isempty(values)
        write_empty(filename, path);
    elseif all(cellfun(@(x) ischar(x) || (isstring(x) && isscalar(x)), values(:)))
        write_text(filename, path, values);
    elseif all(cellfun(@(x) isnumeric(x) && isscalar(x), values(:)))
        write_numeric(filename, path, cell2mat(values(:)));
    else
        for i = 1:numel(values)
            write_value(filename, sprintf('%s/item_%06d', path, i), values{i});
        end
    end
end

function write_numeric(filename, path, value)
    if islogical(value)
        value = uint8(value);
        logical_value = true;
    else
        logical_value = false;
    end
    if isempty(value)
        write_empty(filename, path);
        return;
    end
    if ~isreal(value)
        error('MAGMA:HDF5:ComplexUnsupported', ...
            'Complex values are not exported (%s).', path);
    end
    h5create(filename, path, size(value), 'Datatype', class(value));
    h5write(filename, path, value);
    if logical_value
        h5writeatt(filename, path, 'logical', uint8(1));
    end
end

function write_text(filename, path, value)
    values = cellstr(string(value));
    if isempty(values)
        write_empty(filename, path);
        return;
    end
    bytes = cellfun(@unicode2native, values, ...
        repmat({'UTF-8'}, size(values)), 'UniformOutput', false);
    max_length = max([1; cellfun(@numel, bytes(:))]);
    encoded = zeros(max_length, numel(bytes), 'uint8');
    for i = 1:numel(bytes)
        encoded(1:numel(bytes{i}), i) = bytes{i}(:);
    end
    h5create(filename, path, size(encoded), 'Datatype', 'uint8');
    h5write(filename, path, encoded);
    h5writeatt(filename, path, 'encoding', 'UTF-8');
    h5writeatt(filename, path, 'layout', 'zero_padded_columns');
end

function write_empty(filename, path)
    h5create(filename, path, [1 1], 'Datatype', 'uint8');
    h5write(filename, path, uint8(0));
    h5writeatt(filename, path, 'is_empty', uint8(1));
end

function name = safe_name(name)
    name = regexprep(char(string(name)), '[^A-Za-z0-9_]', '_');
    if isempty(name), name = 'unnamed'; end
end
