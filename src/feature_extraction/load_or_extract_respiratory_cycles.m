function resp_cycles = load_or_extract_respiratory_cycles(data, config)
% LOAD_OR_EXTRACT_RESPIRATORY_CYCLES Reuse a compatible cycle cache or extract anew.
% data is Nsample-by-Nchannel input data. config identifies the recording,
% sampling, channel layout, cache location, and overwrite policy. The
% returned lungs/diaph cycle structs include provenance.loaded_from_cache.

    cache_file = feature_cache_file(config);
    cache_version = current_feature_cache_version();

    force_recompute = isfield(config, 'overwrite_features') && config.overwrite_features;

    if exist(cache_file, 'file') && ~force_recompute
        cached = load(cache_file);
        if is_valid_feature_cache(cached, size(data,1), cache_version, config)
            resp_cycles = cached_resp_cycles(cached);
            resp_cycles.provenance.loaded_from_cache = true;
            log_message(config, 1, ...
                'Loaded cached respiratory cycle extraction results: %s', cache_file);
            return;
        end
        if is_amplitude_method_only_cache_mismatch( ...
                cached, size(data,1), cache_version, config)
            resp_cycles = select_cached_canonical_amplitude( ...
                cached_resp_cycles(cached), config);
            resp_cycles.provenance.loaded_from_cache = true;
            feature_cache_meta = cached.feature_cache_meta;
            feature_cache_meta.amp_method = ...
                resolve_respiration_amplitude_method(config);
            feature_cache_meta.amplitude_reselected_on = char(datetime( ...
                'now', 'Format', 'yyyy-MM-dd HH:mm:ss'));
            save(cache_file, 'resp_cycles', 'feature_cache_meta');
            log_message(config, 1, ...
                ['Loaded cached respiratory cycles and reselected the ' ...
                 'canonical amplitude: %s'], cache_file);
            return;
        end

        warning('Feature cache exists but is incomplete or mismatched. Recomputing: %s', cache_file);
    elseif exist(cache_file, 'file') && force_recompute
        log_message(config, 1, ...
            ['Recomputing respiratory features because ' ...
             'config.overwrite_features is true: %s'], cache_file);
    end

    resp_cycles = extract_respiration_features(data, config);

    [belt_polarity_checked, diaphragm_polarity_flipped] = ...
        belt_polarity_cache_provenance(config);

    feature_cache_meta = struct( ...
        'cache_version', cache_version, ...
        'subject', config.subject, ...
        'measurement', config.measure, ...
        'fs', config.fs, ...
        'n_samples', size(data,1), ...
        'data_columns', {config.data_columns}, ...
        'amp_method', resolve_respiration_amplitude_method(config), ...
        'belt_polarity_checked', belt_polarity_checked, ...
        'diaphragm_polarity_flipped', diaphragm_polarity_flipped, ...
        'created_on', char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss')), ...
        'manual_resp_control', isfield(config.resp, 'manual_control') && config.resp.manual_control);

    cache_dir = fileparts(cache_file);
    if ~isfolder(cache_dir)
        mkdir(cache_dir);
    end

    save(cache_file, 'resp_cycles', 'feature_cache_meta');
    log_message(config, 1, ...
        'Saved respiratory cycle extraction results: %s', cache_file);
end

function ok = is_amplitude_method_only_cache_mismatch( ...
    cached, n_samples, cache_version, config)
% IS_AMPLITUDE_METHOD_ONLY_CACHE_MISMATCH Permit safe amplitude reselection.
% All extraction-defining metadata and the full multi-amplitude cycle schema
% must match. Only the selected canonical amplitude method may differ.

    required_meta = {'cache_version', 'subject', 'measurement', 'fs', ...
        'n_samples', 'data_columns', 'amp_method', ...
        'belt_polarity_checked', 'diaphragm_polarity_flipped'};
    ok = isfield(cached, 'feature_cache_meta') && ...
        isstruct(cached.feature_cache_meta) && ...
        all(isfield(cached.feature_cache_meta, required_meta)) && ...
        isfield(cached, 'resp_cycles') && ...
        is_valid_resp_cycles(cached.resp_cycles, n_samples);
    if ~ok
        return;
    end

    meta = cached.feature_cache_meta;
    requested_method = resolve_respiration_amplitude_method(config);
    [belt_polarity_checked, diaphragm_polarity_flipped] = ...
        belt_polarity_cache_provenance(config);
    ok = isequal(meta.cache_version, cache_version) && ...
        isequal(meta.subject, config.subject) && ...
        isequal(meta.measurement, config.measure) && ...
        isequal(meta.fs, config.fs) && ...
        isequal(meta.n_samples, n_samples) && ...
        isequal(cellstr(string(meta.data_columns)), ...
            cellstr(string(config.data_columns))) && ...
        isequal(logical(meta.belt_polarity_checked), ...
            belt_polarity_checked) && ...
        isequal(logical(meta.diaphragm_polarity_flipped), ...
            diaphragm_polarity_flipped) && ...
        ~strcmp(char(string(meta.amp_method)), requested_method);
end

function resp_cycles = select_cached_canonical_amplitude(resp_cycles, config)
% SELECT_CACHED_CANONICAL_AMPLITUDE Select .amp without moving breath markers.

    method = resolve_respiration_amplitude_method(config);
    source_field = ['amp_' amplitude_method_suffix(method)];
    belt_names = {'lungs', 'diaph'};
    for i = 1:numel(belt_names)
        name = belt_names{i};
        belt = resp_cycles.(name);
        if ~isfield(belt, source_field) || ...
                numel(belt.(source_field)) ~= numel(belt.peak_idx)
            error('MAGMA:Respiration:InvalidAmplitudeCache', ...
                ['Cached %s.%s must contain one value per peak before ' ...
                 'the canonical amplitude can be reselected.'], ...
                name, source_field);
        end
        selected_amplitude = belt.(source_field);
        belt.amp = selected_amplitude(:);
        resp_cycles.(name) = belt;
    end
end

function suffix = amplitude_method_suffix(method)
% AMPLITUDE_METHOD_SUFFIX Map public method names to stored field suffixes.

    switch method
        case 'expiratory'
            suffix = 'exp';
        case 'inspiratory'
            suffix = 'insp';
        case 'symmetric'
            suffix = 'sym';
        otherwise
            error('MAGMA:Respiration:InvalidAmplitudeMethod', ...
                'Unsupported respiratory amplitude method: %s.', method);
    end
end

function cache_file = feature_cache_file(config)
% FEATURE_CACHE_FILE Resolve the MAT-file path for one recording's cycle cache.
% Explicit sub_features_filename/sub_results_path values take precedence
% over the subject/measurement-derived name and general results directory.

    if isfield(config, 'sub_features_filename') && ~isempty(config.sub_features_filename)
        filename = config.sub_features_filename;
    else
        filename = ['Sub' num2str(config.subject) '_M' num2str(config.measure) '_features.mat'];
    end

    if isfield(config, 'sub_results_path') && ~isempty(config.sub_results_path)
        cache_file = fullfile(config.sub_results_path, filename);
    else
        cache_file = fullfile(config.path_results_out, filename);
    end
end

function ok = is_valid_feature_cache(cached, n_samples, cache_version, config)
% IS_VALID_FEATURE_CACHE Check cache metadata, cycle schema, and signal length.
% cached is the struct returned by load; n_samples and cache_version must
% match the current recording, while config supplies identity, fs, columns,
% and the amplitude definition selected for downstream use.

    required_meta = {'cache_version', 'subject', 'measurement', 'fs', ...
        'n_samples', 'data_columns', 'amp_method', ...
        'belt_polarity_checked', 'diaphragm_polarity_flipped'};
    ok = isfield(cached, 'feature_cache_meta') && isstruct(cached.feature_cache_meta) && ...
        all(isfield(cached.feature_cache_meta, required_meta));
    if ~ok
        return;
    end

    meta = cached.feature_cache_meta;
    [belt_polarity_checked, diaphragm_polarity_flipped] = ...
        belt_polarity_cache_provenance(config);
    ok = isequal(meta.cache_version, cache_version) && ...
        isequal(meta.subject, config.subject) && ...
        isequal(meta.measurement, config.measure) && ...
        isequal(meta.fs, config.fs) && ...
        isequal(meta.n_samples, n_samples) && ...
        isequal(cellstr(string(meta.data_columns)), cellstr(string(config.data_columns))) && ...
        isequal(logical(meta.belt_polarity_checked), ...
            belt_polarity_checked) && ...
        isequal(logical(meta.diaphragm_polarity_flipped), ...
            diaphragm_polarity_flipped) && ...
        strcmp(char(string(meta.amp_method)), ...
            resolve_respiration_amplitude_method(config));
    if ~ok
        ok = false;
        return;
    end

    if ~isfield(cached, 'resp_cycles')
        ok = false;
        return;
    end

    ok = is_valid_resp_cycles(cached.resp_cycles, n_samples);
end

function resp_cycles = cached_resp_cycles(cached)
% CACHED_RESP_CYCLES Extract the validated resp_cycles payload from loaded MAT data.

    resp_cycles = cached.resp_cycles;
end

function ok = is_valid_resp_cycles(resp_cycles, n_samples)
% IS_VALID_RESP_CYCLES Check required belt/provenance fields and signal lengths.
% n_samples is the expected number of recording samples; ok is scalar logical.

    amplitude_fields = {'amp', 'amp_exp', 'amp_insp', 'amp_sym'};
    ok = isstruct(resp_cycles) && isfield(resp_cycles, 'lungs') && ...
         isfield(resp_cycles, 'diaph') && isfield(resp_cycles, 'provenance') && ...
         isstruct(resp_cycles.lungs) && isstruct(resp_cycles.diaph) && ...
         isfield(resp_cycles.lungs, 'peak_idx') && isfield(resp_cycles.lungs, 'trough_idx') && ...
         isfield(resp_cycles.diaph, 'peak_idx') && isfield(resp_cycles.diaph, 'trough_idx') && ...
         all(isfield(resp_cycles.lungs, amplitude_fields)) && ...
         all(isfield(resp_cycles.diaph, amplitude_fields)) && ...
         has_aligned_cycle_amplitudes(resp_cycles.lungs, amplitude_fields) && ...
         has_aligned_cycle_amplitudes(resp_cycles.diaph, amplitude_fields) && ...
         is_valid_cycle_provenance(resp_cycles.provenance);
    if ~ok
        return;
    end

    if isfield(resp_cycles.lungs, 'x0') && ~isempty(resp_cycles.lungs.x0) && ...
            numel(resp_cycles.lungs.x0) ~= n_samples
        ok = false;
        return;
    end

    if isfield(resp_cycles.diaph, 'x0') && ~isempty(resp_cycles.diaph.x0) && ...
            numel(resp_cycles.diaph.x0) ~= n_samples
        ok = false;
        return;
    end
end

function ok = has_aligned_cycle_amplitudes(belt, amplitude_fields)
% HAS_ALIGNED_CYCLE_AMPLITUDES Require one value per saved peak.

    n_peaks = numel(belt.peak_idx);
    ok = all(cellfun(@(field) numel(belt.(field)) == n_peaks, ...
        amplitude_fields));
    if ok && isfield(belt, 'peak_t')
        ok = numel(belt.peak_t) == n_peaks;
    end
end

function ok = is_valid_cycle_provenance(provenance)
% IS_VALID_CYCLE_PROVENANCE Validate review state and its associated logical flags.
% provenance must encode an automatic, reviewed-unchanged, or reviewed-edited
% state consistently with manual_review_performed and manual_edits_made.

    required = {'review_status', 'manual_review_performed', ...
        'manual_edits_made', 'loaded_from_cache'};
    valid_states = {'automatic', 'manual_reviewed_unchanged', ...
        'manual_reviewed_edited'};
    review_status = string.empty;
    if isstruct(provenance) && isfield(provenance, 'review_status')
        review_status = string(provenance.review_status);
    end
    ok = isstruct(provenance) && all(isfield(provenance, required)) && ...
        isscalar(review_status) && ismember(char(review_status), valid_states) && ...
        isscalar(provenance.manual_review_performed) && ...
        isscalar(provenance.manual_edits_made) && ...
        isscalar(provenance.loaded_from_cache) && ...
        logical(provenance.manual_review_performed) == ...
            ~strcmp(char(review_status), 'automatic') && ...
        logical(provenance.manual_edits_made) == ...
            strcmp(char(review_status), 'manual_reviewed_edited');
end

function v = current_feature_cache_version()
% CURRENT_FEATURE_CACHE_VERSION Return the schema version required for cycle caches.

    v = 9;
end

function [checked, flipped] = belt_polarity_cache_provenance(config)
% BELT_POLARITY_CACHE_PROVENANCE Resolve preprocessing state for cache matching.

    checked = false;
    flipped = false;
    if ~isfield(config, 'preprocessing') || ...
            ~isstruct(config.preprocessing) || ...
            ~isfield(config.preprocessing, 'belt_polarity_qc') || ...
            ~isstruct(config.preprocessing.belt_polarity_qc)
        return;
    end
    qc = config.preprocessing.belt_polarity_qc;
    if isfield(qc, 'checked') && isscalar(qc.checked)
        checked = logical(qc.checked);
    end
    if isfield(qc, 'flipped') && isscalar(qc.flipped)
        flipped = logical(qc.flipped);
    end
end
