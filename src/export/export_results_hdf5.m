function export_results_hdf5(filename, results, signals_raw, signals_preprocessed)
% EXPORT_RESULTS_HDF5 Write one validated recording in the ML exchange schema.
%
% Inputs:
%   filename             - Destination .h5 path; an existing file is replaced.
%   results              - Final recording-results struct with respiratory
%                          evidence, references, labels, events, review state,
%                          summaries, subject/measurement, and config.fs.
%   signals_raw          - Nsample x Nchannel raw physiological signal matrix.
%   signals_preprocessed - Nsample x Nchannel processed signal matrix.
%
% The v9 file stores sample signals/time under /signals and /time;
% reviewed breath cycles under /resp_cycles, canonical feature traces under
% /resp_features, and compact detector evidence under /detector_diagnostics;
% common-interval metadata under /session_reference, per-belt
% breath-amplitude and raw-excursion references under /resp_reference,
% and SpO2 reference metadata under /spo2_reference; sample x label masks
% and per-label
% metadata under /labels; canonical automatic/reviewed events under /events;
% review rounds under /review; and burden, overlap, phenotype, and recording
% identifiers/configuration under /burden, /overlap, /phenotype_evidence,
% /config, and /meta. Compact pre-final intervals live under /events/candidate.

    filename = char(string(filename));
    validate_export_inputs(filename, results, signals_raw, signals_preprocessed);
    export_schema_version = 'magma_ml_hdf5_v10';
    out_dir = fileparts(filename);
    if ~isempty(out_dir) && ~isfolder(out_dir)
        mkdir(out_dir);
    end
    if isfile(filename)
        delete(filename);
    end

    fs = results.config.fs;
    N = size(signals_preprocessed, 1);
    options = hdf5_export_options(results.config);
    if options.include_raw_signals
        write_numeric(filename, '/signals/raw', ...
            cast_export_signal(signals_raw, options.signal_datatype), options);
    end
    if options.include_preprocessed_signals
        write_numeric(filename, '/signals/preprocessed', ...
            cast_export_signal(signals_preprocessed, options.signal_datatype), ...
            options);
    end
    write_numeric(filename, '/time', (0:N-1)' / fs, options);

    write_value(filename, '/resp_cycles', results.resp_cycles, options);
    write_value(filename, '/session_reference', results.session_reference, options);
    write_value(filename, '/resp_reference/lungs', results.resp_ref.lungs, options);
    write_value(filename, '/resp_reference/diaph', results.resp_ref.diaph, options);
    write_value(filename, '/spo2_reference', results.spo2_ref, options);
    write_value(filename, '/resp_features', results.resp_features, options);
    write_value(filename, '/detector_diagnostics', ...
        results.detector_diagnostics, options);

    write_text(filename, '/labels/names', results.label_names);
    write_numeric(filename, '/labels/available', ...
        uint8(results.label_available(:)'), options);
    write_text(filename, '/labels/availability_reason', results.label_availability_reason);
    write_numeric(filename, '/labels/assessable_mask', ...
        uint8(results.label_assessable_mask), options);
    write_numeric(filename, '/labels/automatic_mask', ...
        uint8(results.mask_automatic), options);
    write_numeric(filename, '/labels/reviewed_mask', ...
        uint8(results.mask_reviewed), options);
    write_numeric(filename, '/labels/review_coverage_mask', ...
        uint8(results.review_coverage_mask), options);
    write_text(filename, '/labels/review_status', results.review_status);
    if isfield(results, 'label_reviewed_available')
        write_numeric(filename, '/labels/reviewed_available', ...
            uint8(results.label_reviewed_available(:)'), options);
    end
    if isfield(results, 'label_reviewed_availability_reason')
        write_text(filename, '/labels/reviewed_availability_reason', ...
            results.label_reviewed_availability_reason);
    end
    if isfield(results, 'label_reviewed_assessable_mask')
        write_numeric(filename, '/labels/reviewed_assessable_mask', ...
            uint8(results.label_reviewed_assessable_mask), options);
    end

    write_events(filename, '/events/automatic', results.events_automatic, options);
    write_events(filename, '/events/reviewed', results.events_reviewed, options);
    write_candidate_event_sets(filename, '/events/candidate', ...
        results.candidate_events, results.label_names, options);
    write_value(filename, '/review/provenance', results.review_provenance, options);
    write_review_history(filename, '/review/history', ...
        results.review_history, options);
    write_value(filename, '/review/scope', results.review_scope, options);

    write_value(filename, '/burden/automatic', ...
        results.label_burden_automatic, options);
    write_value(filename, '/burden/reviewed', ...
        results.label_burden_reviewed, options);
    write_value(filename, '/overlap/automatic', ...
        results.label_overlap_summary_automatic, options);
    write_value(filename, '/overlap/reviewed', ...
        results.label_overlap_summary_reviewed, options);
    write_value(filename, '/evidence_summary/automatic', ...
        results.label_evidence_summary_automatic, options);
    write_value(filename, '/evidence_summary/reviewed', ...
        results.label_evidence_summary_reviewed, options);
    write_value(filename, '/phenotype_evidence', ...
        results.db_phenotype_evidence, options);
    write_value(filename, '/config', results.config, options);

    write_numeric(filename, '/meta/subject', results.subject, options);
    write_numeric(filename, '/meta/measurement', results.measure, options);
    write_numeric(filename, '/meta/fs', fs, options);
    if isfield(results, 'analysis_id')
        write_text(filename, '/meta/analysis_id', results.analysis_id);
    end
    write_text(filename, '/meta/export_schema_version', export_schema_version);
    write_text(filename, '/meta/upstream_input_preprocessing', ...
        results.upstream_input_preprocessing);
end

function validate_export_inputs(filename, results, raw, preprocessed)
% VALIDATE_EXPORT_INPUTS Enforce recording, label-order, and sample alignment.
% raw and preprocessed must be numeric matrices with equal row counts.
% results must contain the frozen 11-label vectors, Nsample x 11 masks,
% canonical events, positive config.fs, and session-reference metadata.

    if isempty(filename)
        error('MAGMA:HDF5:InvalidFilename', 'A nonempty output filename is required.');
    end
    required = {'config', 'resp_cycles', 'resp_features', ...
        'session_reference', 'resp_ref', ...
        'spo2_ref', 'label_names', ...
        'label_available', 'label_availability_reason', 'label_assessable_mask', ...
        'mask_automatic', 'mask_reviewed', 'review_coverage_mask', 'review_status', ...
        'events_automatic', 'events_reviewed', 'label_burden_automatic', ...
        'label_burden_reviewed', 'label_overlap_summary_automatic', ...
        'label_overlap_summary_reviewed', 'db_phenotype_evidence', ...
        'label_reviewed_available', 'label_reviewed_availability_reason', ...
        'label_reviewed_assessable_mask', ...
        'candidate_events', 'detector_diagnostics', ...
        'review_provenance', 'review_history', 'review_scope', ...
        'label_evidence_summary_automatic', ...
        'label_evidence_summary_reviewed', ...
        'upstream_input_preprocessing', ...
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
    expected = get_labels('short');
    if ~isequal(cellstr(string(results.label_names)), expected)
        error('MAGMA:HDF5:LabelOrder', 'HDF5 export requires the frozen 11-label order.');
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
        'mask_automatic', 'mask_reviewed', 'review_coverage_mask'};
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
    validate_canonical_events(results.events_automatic, results.config.fs, expected);
    validate_canonical_events(results.events_reviewed, results.config.fs, expected);
    validate_candidate_event_sets( ...
        results.candidate_events, results.config.fs, expected);
    validate_session_reference(results.session_reference, N, ...
        results.config.fs, results.measure);
end

function validate_candidate_event_sets(sets, fs, labels)
% VALIDATE_CANDIDATE_EVENT_SETS Enforce the frozen compact candidate schema.

    expected_fields = fieldnames(empty_candidate_events());
    if ~isstruct(sets) || ~isscalar(sets) || ...
            ~isequal(fieldnames(sets), labels(:))
        error('MAGMA:HDF5:CandidateLabelAlignment', ...
            'candidate_events must contain one field per frozen label in order.');
    end
    allowed_belts = {'', 'lungs', 'diaph', 'both', 'combined'};
    allowed_reasons = {'', 'too_short', 'no_support', 'unevaluable'};
    for i = 1:numel(labels)
        candidates = sets.(labels{i});
        if ~isstruct(candidates) || ...
                ~isequal(fieldnames(candidates), expected_fields)
            error('MAGMA:HDF5:CandidateSchema', ...
                'candidate_events.%s does not use the canonical schema.', ...
                labels{i});
        end
        for j = 1:numel(candidates)
            candidate = candidates(j);
            validate_candidate_coordinates(candidate, fs, labels{i});
            belt = char(string(candidate.belt));
            reason = char(string(candidate.rejection_reason));
            accepted = candidate.accepted;
            if ~ismember(belt, allowed_belts) || ...
                    ~ismember(reason, allowed_reasons) || ...
                    ~(islogical(accepted) || isnumeric(accepted)) || ...
                    ~isscalar(accepted) || ~isfinite(double(accepted)) || ...
                    ~ismember(double(accepted), [0 1]) || ...
                    (logical(accepted) && ~isempty(reason)) || ...
                    (~logical(accepted) && isempty(reason)) || ...
                    ~isnumeric(candidate.uncertainty_sec) || ...
                    ~isscalar(candidate.uncertainty_sec) || ...
                    ~isfinite(candidate.uncertainty_sec) || ...
                    candidate.uncertainty_sec < 0
                error('MAGMA:HDF5:CandidateMetadata', ...
                    'candidate_events.%s contains invalid compact metadata.', ...
                    labels{i});
            end
        end
    end
end

function validate_candidate_coordinates(candidate, fs, label)
% VALIDATE_CANDIDATE_COORDINATES Check half-open candidate timing.

    numeric_fields = {'start_idx','end_idx','start_t','end_t','duration'};
    if any(~cellfun(@(name) isnumeric(candidate.(name)) && ...
            isscalar(candidate.(name)) && isfinite(candidate.(name)), ...
            numeric_fields))
        error('MAGMA:HDF5:CandidateTiming', ...
            'candidate_events.%s contains non-finite coordinates.', label);
    end
    start_idx = round(candidate.start_idx);
    end_idx = round(candidate.end_idx);
    expected_start_t = (start_idx - 1) / fs;
    expected_end_t = end_idx / fs;
    expected_duration = (end_idx - start_idx + 1) / fs;
    tolerance = 10 * eps(max(1, abs(expected_end_t)));
    if start_idx < 1 || end_idx < start_idx || ...
            abs(candidate.start_t - expected_start_t) > tolerance || ...
            abs(candidate.end_t - expected_end_t) > tolerance || ...
            abs(candidate.duration - expected_duration) > tolerance
        error('MAGMA:HDF5:CandidateTiming', ...
            'candidate_events.%s must use half-open index-derived timing.', label);
    end
end

function validate_session_reference(reference, N, fs, measurement)
% VALIDATE_SESSION_REFERENCE Check schema identity and index-derived timing.
% For an available interval, reference indices must fall within N samples;
% start_t, end_t, and duration use half-open boundaries derived using fs.

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
% VALIDATE_CANONICAL_EVENTS Enforce event fields, label names, and sample timing.
% events must have type, start_idx, end_idx, start_t, end_t, duration, and
% belt; times in seconds follow the half-open convention implied by fs.

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

function write_events(filename, path, events, options)
% WRITE_EVENTS Export a canonical event array as parallel HDF5 datasets.
% Index fields are samples, time/duration fields are seconds, and type/belt
% are UTF-8 text columns below path.

    write_text(filename, [path '/type'], event_field(events, 'type', 'text'));
    write_numeric(filename, [path '/start_idx'], ...
        event_field(events, 'start_idx', 'numeric'), options);
    write_numeric(filename, [path '/end_idx'], ...
        event_field(events, 'end_idx', 'numeric'), options);
    write_numeric(filename, [path '/start_t'], ...
        event_field(events, 'start_t', 'numeric'), options);
    write_numeric(filename, [path '/end_t'], ...
        event_field(events, 'end_t', 'numeric'), options);
    write_numeric(filename, [path '/duration'], ...
        event_field(events, 'duration', 'numeric'), options);
    write_text(filename, [path '/belt'], event_field(events, 'belt', 'text'));
end

function write_candidate_event_sets(filename, path, sets, labels, options)
% WRITE_CANDIDATE_EVENT_SETS Export compact candidates by containing label.

    labels = cellstr(string(labels));
    for i = 1:numel(labels)
        write_candidate_events(filename, [path '/' labels{i}], ...
            sets.(labels{i}), options);
    end
end

function write_candidate_events(filename, path, candidates, options)
% WRITE_CANDIDATE_EVENTS Export the frozen nine fields as parallel datasets.

    write_numeric(filename, [path '/start_idx'], ...
        event_field(candidates, 'start_idx', 'numeric'), options);
    write_numeric(filename, [path '/end_idx'], ...
        event_field(candidates, 'end_idx', 'numeric'), options);
    write_numeric(filename, [path '/start_t'], ...
        event_field(candidates, 'start_t', 'numeric'), options);
    write_numeric(filename, [path '/end_t'], ...
        event_field(candidates, 'end_t', 'numeric'), options);
    write_numeric(filename, [path '/duration'], ...
        event_field(candidates, 'duration', 'numeric'), options);
    write_text(filename, [path '/belt'], ...
        event_field(candidates, 'belt', 'text'));
    write_numeric(filename, [path '/accepted'], logical( ...
        event_field(candidates, 'accepted', 'numeric')), options);
    write_text(filename, [path '/rejection_reason'], ...
        event_field(candidates, 'rejection_reason', 'text'));
    write_numeric(filename, [path '/uncertainty_sec'], ...
        event_field(candidates, 'uncertainty_sec', 'numeric'), options);
end

function write_review_history(filename, path, history, options)
% WRITE_REVIEW_HISTORY Export each immutable manual-review round.
% history is a struct array whose round_<id> groups contain provenance,
% canonical events, sample x label masks, coverage/status, and optional
% reviewer identity, notes, schema version, and active-round flag.

    write_numeric(filename, [path '/number_of_rounds'], numel(history), options);
    for i = 1:numel(history)
        round_path = sprintf('%s/round_%06d', path, history(i).round_id);
        write_numeric(filename, [round_path '/round_id'], ...
            history(i).round_id, options);
        write_text(filename, [round_path '/timestamp'], history(i).timestamp);
        write_text(filename, [round_path '/reviewer_role'], history(i).reviewer_role);
        write_text(filename, [round_path '/start_from'], history(i).start_from);
        write_numeric(filename, [round_path '/source_review_round'], ...
            history(i).source_review_round, options);
        if isfield(history, 'source_analysis_id')
            write_text(filename, [round_path '/source_analysis_id'], ...
                history(i).source_analysis_id);
        end
        write_events(filename, [round_path '/events'], history(i).events, options);
        write_numeric(filename, [round_path '/mask'], ...
            uint8(history(i).mask), options);
        write_numeric(filename, [round_path '/review_mask'], ...
            uint8(history(i).review_mask), options);
        write_text(filename, [round_path '/review_status'], ...
            history(i).review_status);
        write_text(filename, [round_path '/changed_labels'], ...
            history(i).changed_labels);
        if isfield(history, 'reviewer_id')
            write_text(filename, [round_path '/reviewer_id'], history(i).reviewer_id);
        end
        if isfield(history, 'notes')
            write_text(filename, [round_path '/notes'], history(i).notes);
        end
        if isfield(history, 'schema_version')
            write_text(filename, [round_path '/schema_version'], ...
                history(i).schema_version);
        end
        if isfield(history, 'accepted_as_active')
            write_numeric(filename, [round_path '/accepted_as_active'], ...
                uint8(history(i).accepted_as_active), options);
        end
    end
end

function values = event_field(events, name, kind)
% EVENT_FIELD Collect one canonical event field in export orientation.
% kind is "text" for a cell row; all other kinds produce a numeric column.

    if isempty(events) || ~isfield(events, name)
        if strcmp(kind, 'text'), values = {}; else, values = []; end
    elseif strcmp(kind, 'text')
        values = {events.(name)};
    else
        values = [events.(name)]';
    end
end

function write_value(filename, path, value, options)
% WRITE_VALUE Recursively serialize a supported MATLAB value below an HDF5 path.
% Structs, cells, text, numeric/logical values, and empty values are encoded
% by type-specific writers; unsupported classes raise an export error.

    if isstruct(value)
        if isempty(value)
            write_empty(filename, [path '/empty_struct']);
        elseif isscalar(value)
            names = fieldnames(value);
            for i = 1:numel(names)
                write_value(filename, [path '/' safe_name(names{i})], ...
                    value.(names{i}), options);
            end
        else
            write_struct_array(filename, path, value, options);
        end
    elseif isnumeric(value) || islogical(value)
        write_numeric(filename, path, value, options);
    elseif ischar(value) || isstring(value)
        write_text(filename, path, value);
    elseif iscell(value)
        write_cell(filename, path, value, options);
    else
        error('MAGMA:HDF5:UnsupportedType', ...
            'Unsupported value at %s (%s).', path, class(value));
    end
end

function write_struct_array(filename, path, values, options)
% WRITE_STRUCT_ARRAY Recursively write scalar fields or indexed struct groups.

    names = fieldnames(values);
    for i = 1:numel(names)
        parts = {values.(names{i})};
        if all(cellfun(@(x) isnumeric(x) && isscalar(x), parts))
            write_numeric(filename, [path '/' safe_name(names{i})], ...
                cell2mat(parts(:)), options);
        elseif all(cellfun(@(x) ischar(x) || (isstring(x) && isscalar(x)), parts))
            write_text(filename, [path '/' safe_name(names{i})], parts);
        else
            for j = 1:numel(values)
                item_path = sprintf('%s/item_%06d/%s', path, j, safe_name(names{i}));
                write_value(filename, item_path, values(j).(names{i}), options);
            end
        end
    end
end

function write_cell(filename, path, values, options)
% WRITE_CELL Encode a homogeneous cell array or recursively index mixed cells.
% All-text cells share one byte matrix; scalar numeric/logical cells share a
% numeric array; other contents are written below item_<index> groups.

    if isempty(values)
        write_empty(filename, path);
    elseif all(cellfun(@(x) ischar(x) || (isstring(x) && isscalar(x)), values(:)))
        write_text(filename, path, values);
    elseif all(cellfun(@(x) isnumeric(x) && isscalar(x), values(:)))
        write_numeric(filename, path, cell2mat(values(:)), options);
    else
        for i = 1:numel(values)
            write_value(filename, sprintf('%s/item_%06d', path, i), ...
                values{i}, options);
        end
    end
end

function options = hdf5_export_options(config)
% HDF5_EXPORT_OPTIONS Resolve and validate export-only storage settings.

    options = struct( ...
        'include_raw_signals', get_config_value( ...
            config, 'HDF5', 'include_raw_signals', false), ...
        'include_preprocessed_signals', get_config_value( ...
            config, 'HDF5', 'include_preprocessed_signals', true), ...
        'signal_datatype', lower(char(string(get_config_value( ...
            config, 'HDF5', 'signal_datatype', 'single')))), ...
        'compression_level', get_config_value( ...
            config, 'HDF5', 'compression_level', 4));
    logical_fields = {'include_raw_signals', 'include_preprocessed_signals'};
    for i = 1:numel(logical_fields)
        value = options.(logical_fields{i});
        if ~(islogical(value) || isnumeric(value)) || ~isscalar(value) || ...
                ~isfinite(double(value)) || ~ismember(double(value), [0 1])
            error('MAGMA:HDF5:InvalidExportSetting', ...
                'config.HDF5.%s must be a scalar logical value.', ...
                logical_fields{i});
        end
        options.(logical_fields{i}) = logical(value);
    end
    if ~ismember(options.signal_datatype, {'single', 'double', 'native'})
        error('MAGMA:HDF5:InvalidExportSetting', ...
            ['config.HDF5.signal_datatype must be ''single'', ' ...
             '''double'', or ''native''.']);
    end
    level = options.compression_level;
    if ~isnumeric(level) || ~isscalar(level) || ~isfinite(level) || ...
            level < 0 || level > 9 || level ~= round(level)
        error('MAGMA:HDF5:InvalidExportSetting', ...
            'config.HDF5.compression_level must be an integer from 0 to 9.');
    end
    options.compression_level = double(level);
end

function signal = cast_export_signal(signal, datatype)
% CAST_EXPORT_SIGNAL Cast only the HDF5 signal payload, never analysis data.

    switch datatype
        case 'single'
            signal = single(signal);
        case 'double'
            signal = double(signal);
        case 'native'
            % Preserve the caller's numeric class.
    end
end

function tf = should_compress_numeric(path, value, options)
% SHOULD_COMPRESS_NUMERIC Compress sizable arrays and all signal/label arrays.

    byte_count = numel(value) * numeric_class_bytes(class(value));
    priority_path = startsWith(path, '/signals/') || ...
        startsWith(path, '/labels/');
    tf = options.compression_level > 0 && numel(value) > 1 && ...
        (byte_count >= 1024 || priority_path);
end

function chunk_size = numeric_chunk_size(value)
% NUMERIC_CHUNK_SIZE Limit chunks to approximately one MiB.

    chunk_size = size(value);
    max_elements = max(1, floor(1024^2 / ...
        numeric_class_bytes(class(value))));
    while prod(chunk_size) > max_elements
        [~, dimension] = max(chunk_size);
        chunk_size(dimension) = ceil(chunk_size(dimension) / 2);
    end
end

function bytes = numeric_class_bytes(class_name)
% NUMERIC_CLASS_BYTES Return storage width for supported numeric classes.

    switch class_name
        case {'double', 'uint64', 'int64'}
            bytes = 8;
        case {'single', 'uint32', 'int32'}
            bytes = 4;
        case {'uint16', 'int16'}
            bytes = 2;
        otherwise
            bytes = 1;
    end
end

function write_numeric(filename, path, value, options)
% WRITE_NUMERIC Create one numeric HDF5 dataset, preserving MATLAB dimensions.
% Logical values are converted to uint8; empty values use the shared empty marker.

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
    create_args = {'Datatype', class(value)};
    if should_compress_numeric(path, value, options)
        create_args = [create_args, ...
            {'ChunkSize', numeric_chunk_size(value), ...
             'Deflate', options.compression_level}];
    end
    h5create(filename, path, size(value), create_args{:});
    h5write(filename, path, value);
    if logical_value
        h5writeatt(filename, path, 'logical', uint8(1));
    end
end

function write_text(filename, path, value)
% WRITE_TEXT Store text values as zero-padded UTF-8 byte columns.
% Scalar strings, character arrays, and string/cell arrays are accepted.

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
% WRITE_EMPTY Mark an absent value with a placeholder dataset and attribute.

    h5create(filename, path, [1 1], 'Datatype', 'uint8');
    h5write(filename, path, uint8(0));
    h5writeatt(filename, path, 'is_empty', uint8(1));
end

function name = safe_name(name)
% SAFE_NAME Convert an arbitrary struct field to a nonempty HDF5 path component.

    name = regexprep(char(string(name)), '[^A-Za-z0-9_]', '_');
    if isempty(name), name = 'unnamed'; end
end
