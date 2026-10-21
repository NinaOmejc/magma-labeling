function [resp_cycles, cancelled] = load_or_extract_respiratory_cycles(data, config)
% LOAD_OR_EXTRACT_RESPIRATORY_CYCLES Reuse a compatible cycle cache or extract anew.
% data is Nsample-by-Nchannel input data. config identifies the recording,
% sampling, channel layout, cache location, and overwrite policy. The
% returned lungs/diaph cycle structs include provenance.loaded_from_cache.

    cancelled = false;
    recording_observations = recording_observation('load', config);
    config.recording_observations = recording_observations;
    cache_file = feature_cache_file(config);
    cache_version = current_feature_cache_version();

    force_recompute = isfield(config, 'overwrite_features') && config.overwrite_features;

    if exist(cache_file, 'file') && ~force_recompute
        cached = load(cache_file);
        if is_valid_feature_cache(cached, size(data,1), cache_version, config)
            resp_cycles = cached_resp_cycles(cached);
            feature_cache_meta = cached.feature_cache_meta;
            [resp_cycles, observation_changed] = apply_thoracic_observation(resp_cycles, data, config);
            [resp_cycles, landmarks_valid, repaired_belts, repair_notes] = ...
                repair_cached_cycle_landmarks(resp_cycles, config);
            if landmarks_valid
                if ~isempty(repaired_belts)
                    feature_cache_meta = cached.feature_cache_meta;
                    feature_cache_meta.landmarks_repaired_on = char(datetime( ...
                        'now', 'Format', 'yyyy-MM-dd HH:mm:ss'));
                    feature_cache_meta.landmarks_repaired_belts = repaired_belts;
                    warning('MAGMA:Respiration:CachedLandmarksRepaired', ...
                        ['Invalid cached trough landmarks were repaired from ' ...
                         'the saved belt signal without changing peak locations ' ...
                         '(%s). %s'], ...
                        strjoin(repaired_belts, ', '), strjoin(repair_notes, ' '));
                end
                [resp_cycles,cancelled] = accept_cached_features(resp_cycles,cached, ...
                    feature_cache_meta,data,config,cache_file,observation_changed || ~isempty(repaired_belts));
                if cancelled, return; end
                resp_cycles.provenance.loaded_from_cache = true;
                log_message(config, 1, ...
                    'Loaded cached respiratory cycle extraction results: %s', cache_file);
                return;
            end
            warning('MAGMA:Respiration:InvalidCachedLandmarks', ...
                ['The cached respiratory landmarks could not be repaired ' ...
                 'without changing reviewed peaks. Recomputing: %s'], cache_file);
        end
        if is_amplitude_method_only_cache_mismatch( ...
                cached, size(data,1), cache_version, config)
            if get_config_value(config,'resp','recheck_cached',false)
                error('MAGMA:Respiration:RecheckAmplitudeMismatch', ...
                    'Recheck preserves the saved amplitude method. Set resp.amp_method to %s before reopening %s.',cached.feature_cache_meta.amp_method,cache_file);
            end
            resp_cycles = cached_resp_cycles(cached);
            [resp_cycles, ~] = apply_thoracic_observation(resp_cycles, data, config);
            [resp_cycles, landmarks_valid, repaired_belts, repair_notes] = ...
                repair_cached_cycle_landmarks(resp_cycles, config);
            if landmarks_valid
                resp_cycles = select_cached_canonical_amplitude( ...
                    resp_cycles, config);
                feature_cache_meta = cached.feature_cache_meta;
                feature_cache_meta.amp_method = ...
                    resolve_respiration_amplitude_method(config);
                feature_cache_meta.amplitude_reselected_on = char(datetime( ...
                    'now', 'Format', 'yyyy-MM-dd HH:mm:ss'));
                if ~isempty(repaired_belts)
                    feature_cache_meta.landmarks_repaired_on = char(datetime( ...
                        'now', 'Format', 'yyyy-MM-dd HH:mm:ss'));
                    feature_cache_meta.landmarks_repaired_belts = repaired_belts;
                    warning('MAGMA:Respiration:CachedLandmarksRepaired', ...
                        ['Invalid cached trough landmarks were repaired from ' ...
                         'the saved belt signal without changing peak locations ' ...
                         '(%s). %s'], strjoin(repaired_belts, ', '), ...
                        strjoin(repair_notes, ' '));
                end
                [resp_cycles,cancelled] = accept_cached_features(resp_cycles,cached, ...
                    feature_cache_meta,data,config,cache_file,true);
                if cancelled, return; end
                resp_cycles.provenance.loaded_from_cache = true;
                log_message(config, 1, ...
                    ['Loaded cached respiratory cycles and reselected the ' ...
                     'canonical amplitude: %s'], cache_file);
                return;
            end
            warning('MAGMA:Respiration:InvalidCachedLandmarks', ...
                ['The cached respiratory landmarks could not be repaired ' ...
                 'without changing reviewed peaks. Recomputing: %s'], cache_file);
        end

        if get_config_value(config,'resp','recheck_cached',false)
            error('MAGMA:Respiration:RecheckCacheMismatch','Cannot recheck incompatible cache; no saved landmarks were regenerated: %s',cache_file);
        end
        if isfield(cached,'resp_cycles') && has_reviewed_respiration_landmarks(cached.resp_cycles)
            error('MAGMA:Respiration:ReviewedFeatureCacheMismatch', ...
                ['Reviewed respiratory feature cache is incompatible and ' ...
                 'will not be overwritten: %s. Inspect the cache or set ' ...
                 'config.overwrite_features = true to explicitly recompute.'], ...
                cache_file);
        end
        warning('Feature cache exists but is incomplete or mismatched. Recomputing: %s', cache_file);
    elseif exist(cache_file, 'file') && force_recompute
        log_message(config, 1, ...
            ['Recomputing respiratory features because ' ...
             'config.overwrite_features is true: %s'], cache_file);
    end

    previous_state = respiratory_artifact_checkpoint('load',config);
    replacing_cache = isfile(cache_file);
    resp_cycles = extract_respiration_features(data, config);
    recording_observations = recording_observation('load', config);
    config.recording_observations = recording_observations;
    [resp_cycles, ~] = apply_thoracic_observation(resp_cycles, data, config);

    [belt_polarity_checked, thoracic_polarity_flipped, diaphragm_polarity_flipped] = ...
        respiratory_belt_polarity_state(config);
    [absolute_polarity_checked, absolute_polarity_flipped] = ...
        absolute_polarity_cache_provenance(config);

    feature_cache_meta = struct( ...
        'cache_version', cache_version, ...
        'subject', config.subject, ...
        'measurement', config.measure, ...
        'fs', config.fs, ...
        'n_samples', size(data,1), ...
        'data_columns', {config.data_columns}, ...
        'amp_method', resolve_respiration_amplitude_method(config), ...
        'belt_polarity_checked', belt_polarity_checked, ...
        'thoracic_polarity_flipped', thoracic_polarity_flipped, ...
        'diaphragm_polarity_flipped', diaphragm_polarity_flipped, ...
        'absolute_polarity_checked', absolute_polarity_checked, ...
        'absolute_polarity_flipped', absolute_polarity_flipped, ...
        'belt_polarity_qc', get_config_value(config, 'preprocessing', 'belt_polarity_qc', struct()), ...
        'absolute_polarity_qc', get_config_value(config, 'preprocessing', 'absolute_polarity_qc', struct()), ...
        'created_on', char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss')), ...
        'manual_resp_control', isfield(config.resp, 'manual_control') && config.resp.manual_control);

    cache_dir = fileparts(cache_file);
    if ~isfolder(cache_dir)
        mkdir(cache_dir);
    end

    state = respiratory_artifact_state(resp_cycles,config,size(data,1));
    if replacing_cache || ~isempty(state.artifact_intervals_idx)
        state.revision = previous_state.revision+1; state.pending_reanalysis = true;
        state.timestamp = char(datetime('now','TimeZone','UTC','Format','yyyy-MM-dd HH:mm:ss.SSS XXX'));
        state.reviewer_role = get_config_value(config,'LabelEdit','reviewer_role','researcher');
        state.annotation_source = 'respiration_feature_gui';
        if ~resp_cycles.provenance.manual_review_performed
            state.reviewer_role = 'system'; state.annotation_source = 'respiratory_feature_extraction';
        end
    end
    resp_cycles.artifact_annotation = artifact_metadata(state);
    payload = struct('resp_cycles',resp_cycles,'feature_cache_meta',feature_cache_meta, ...
        'recording_observations',recording_observations,'respiratory_artifact_state',state);
    atomic_save_mat(cache_file,payload);
    respiratory_artifact_checkpoint('publish',config,state);
    log_message(config, 1, ...
        'Saved respiratory cycle extraction results: %s', cache_file);
end

function [cycles,cancelled] = accept_cached_features(cycles,cached,meta,data,config,filename,dirty)
% Recheck the saved cycles before any migration/write, so Cancel is byte-safe.
    original = cached.resp_cycles;
    cancelled = false;
    N = size(data,1);
    legacy = ~isfield(cycles,'artifact_intervals_idx');
    legacy_state = struct();
    if isfield(cached,'respiratory_artifact_state'), legacy_state = cached.respiratory_artifact_state; end
    [cycles,migrated] = migrate_respiratory_artifacts(cycles,N,legacy_state);
    dirty = dirty || legacy || migrated;
    shared_semantics_changed = legacy && ~isempty(cycles.artifact_intervals_idx);
    state = respiratory_artifact_state(cycles,config,N);
    cycles.artifact_annotation = artifact_metadata(state);
    if get_config_value(config,'resp','recheck_cached',false)
        % Reviewed atomically replaces this cache; Cancel leaves it untouched.
        [~,~,accepted] = manual_edit_respiration_features(data,cycles.lungs,cycles.diaph, ...
            config,@commit_review,filename,cycles.artifact_intervals_idx);
        if ~accepted, cycles = original; cancelled = true; return; end
        % The cache callback ran within the observation transaction.
        saved = load(filename); cycles = saved.resp_cycles;
        respiratory_artifact_checkpoint('publish',config,saved.respiratory_artifact_state);
    elseif dirty || ~isfield(cached,'respiratory_artifact_state')
        if shared_semantics_changed
            state = advance_artifact_revision(state,config);
            state.reviewer_role = 'system'; state.annotation_source = 'respiratory_artifact_migration';
            cycles.artifact_annotation = artifact_metadata(state);
        end
        cached.resp_cycles = cycles; cached.feature_cache_meta = meta;
        cached.recording_observations = config.recording_observations;
        cached.respiratory_artifact_state = state;
        atomic_save_mat(filename,cached);
        if shared_semantics_changed, respiratory_artifact_checkpoint('publish',config,state); end
    end

    function result = commit_review(lungs,diaph,observation,artifacts)
        current = respiratory_artifact_checkpoint('load',config);
        if current.revision ~= state.revision
            error('MAGMA:Respiration:ChangedDuringReview','Respiratory features changed in another session; reopen before saving.');
        end
        changed = shared_semantics_changed || respiration_breath_landmarks_changed(cycles.lungs,lungs) || ...
            respiration_breath_landmarks_changed(cycles.diaph,diaph) || ...
            ~isequal(cycles.artifact_intervals_idx,artifacts);
        cycles.lungs = lungs; cycles.diaph = diaph;
        cycles.artifact_intervals_idx = artifacts;
        cycles.provenance.manual_review_performed = true;
        cycles.provenance.manual_edits_made = cycles.provenance.manual_edits_made || changed;
        cycles.provenance.review_status = 'manual_reviewed_unchanged';
        if cycles.provenance.manual_edits_made, cycles.provenance.review_status = 'manual_reviewed_edited'; end
        if changed
            state = advance_artifact_revision(state,config);
        end
        cycles.artifact_annotation = artifact_metadata(state);
        state = respiratory_artifact_state(cycles,config,N);
        cached.resp_cycles = cycles; cached.feature_cache_meta = meta;
        cached.recording_observations = observation;
        cached.respiratory_artifact_state = state;
        atomic_save_mat(filename,cached);
        result = state;
    end
end

function metadata = artifact_metadata(state)
    metadata = rmfield(state,{'subject','measurement','artifact_intervals_idx','evidence_intervals_idx', ...
        'lungs','diaph','lungs_evidence','diaph_evidence'});
end

function state = advance_artifact_revision(state,config)
    state.revision = state.revision + 1;
    state.timestamp = char(datetime('now','TimeZone','UTC','Format','yyyy-MM-dd HH:mm:ss.SSS XXX'));
    state.reviewer_role = get_config_value(config,'LabelEdit','reviewer_role','researcher');
    state.annotation_source = 'respiration_feature_gui';
    state.pending_reanalysis = true;
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
    [belt_polarity_checked, thoracic_polarity_flipped, diaphragm_polarity_flipped] = ...
        respiratory_belt_polarity_state(config);
    [absolute_polarity_checked, absolute_polarity_flipped] = ...
        absolute_polarity_cache_provenance(config);
    ok = compatible_cache_version(meta, cache_version) && ...
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
        isequal(cache_logical(meta, 'thoracic_polarity_flipped'), ...
            thoracic_polarity_flipped) && ...
        isequal(cache_logical(meta, 'absolute_polarity_checked'), ...
            absolute_polarity_checked) && ...
        isequal(cache_logical(meta, 'absolute_polarity_flipped'), ...
            absolute_polarity_flipped) && ...
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
    [belt_polarity_checked, thoracic_polarity_flipped, diaphragm_polarity_flipped] = ...
        respiratory_belt_polarity_state(config);
    [absolute_polarity_checked, absolute_polarity_flipped] = ...
        absolute_polarity_cache_provenance(config);
    ok = compatible_cache_version(meta, cache_version) && ...
        isequal(meta.subject, config.subject) && ...
        isequal(meta.measurement, config.measure) && ...
        isequal(meta.fs, config.fs) && ...
        isequal(meta.n_samples, n_samples) && ...
        isequal(cellstr(string(meta.data_columns)), cellstr(string(config.data_columns))) && ...
        isequal(logical(meta.belt_polarity_checked), ...
            belt_polarity_checked) && ...
        isequal(logical(meta.diaphragm_polarity_flipped), ...
            diaphragm_polarity_flipped) && ...
        isequal(cache_logical(meta, 'thoracic_polarity_flipped'), ...
            thoracic_polarity_flipped) && ...
        isequal(cache_logical(meta, 'absolute_polarity_checked'), ...
            absolute_polarity_checked) && ...
        isequal(cache_logical(meta, 'absolute_polarity_flipped'), ...
            absolute_polarity_flipped) && ...
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

function [resp_cycles, valid, repaired_belts, repair_notes] = ...
        repair_cached_cycle_landmarks(resp_cycles, config)
% REPAIR_CACHED_CYCLE_LANDMARKS Rebuild invalid troughs without moving peaks.
% Existing valid pair-anchored manual trough overrides survive recomputation.

    valid = true;
    repaired_belts = {};
    repair_notes = {};
    belt_names = {'lungs', 'diaph'};
    for i = 1:numel(belt_names)
        name = belt_names{i};
        belt = resp_cycles.(name);
        [belt_valid, original_message] = ...
            validate_respiration_cycle_landmarks(belt);
        if belt_valid
            continue;
        end
        if has_reviewed_respiration_landmarks(resp_cycles)
            error('MAGMA:Respiration:ReviewedFeatureCacheMismatch', ...
                ['Reviewed %s landmarks are incompatible: %s. No landmarks were changed. ' ...
                 'Restore a compatible backup or explicitly review/recompute the features.'], ...
                name, original_message);
        end
        if ~isfield(belt, 'x0') || isempty(belt.x0) || ...
                ~isfield(belt, 'peak_idx')
            valid = false;
            repair_notes{end+1} = sprintf('%s: %s', ...
                name, original_message); %#ok<AGROW>
            continue;
        end
        original_peak_idx = belt.peak_idx(:);
        try
            repaired = recompute_respiration_breath_fields( ...
                belt, belt.x0, original_peak_idx, config);
            [repaired_valid, repaired_message] = ...
                validate_respiration_cycle_landmarks(repaired);
        catch err
            repaired_valid = false;
            repaired_message = err.message;
        end
        if repaired_valid && ...
                isequal(repaired.peak_idx(:), original_peak_idx)
            resp_cycles.(name) = repaired;
            repaired_belts{end+1} = name; %#ok<AGROW>
            repair_notes{end+1} = sprintf('%s: %s', ...
                name, original_message); %#ok<AGROW>
        else
            valid = false;
            repair_notes{end+1} = sprintf( ...
                '%s: %s Repair failed: %s', ...
                name, original_message, repaired_message); %#ok<AGROW>
        end
    end
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

    v = 10; % Per-belt correction metadata; older code must not reuse thoracic flips.
end

function ok = compatible_cache_version(meta, current_version)
% Version 9 predates thoracic correction and safely implies no thoracic flip.
    ok = isequal(meta.cache_version, 9) || ...
        (isequal(meta.cache_version, current_version) && ...
         isfield(meta, 'thoracic_polarity_flipped'));
end

function [checked, flipped] = absolute_polarity_cache_provenance(config)
% ABSOLUTE_POLARITY_CACHE_PROVENANCE Track the final common belt orientation.

    checked = false;
    flipped = false;
    if ~isfield(config, 'preprocessing') || ...
            ~isstruct(config.preprocessing) || ...
            ~isfield(config.preprocessing, 'absolute_polarity_qc') || ...
            ~isstruct(config.preprocessing.absolute_polarity_qc)
        return;
    end
    qc = config.preprocessing.absolute_polarity_qc;
    if isfield(qc, 'absolute_polarity_checked') && ...
            isscalar(qc.absolute_polarity_checked)
        checked = logical(qc.absolute_polarity_checked);
    end
    if isfield(qc, 'absolute_polarity_flipped') && ...
            isscalar(qc.absolute_polarity_flipped)
        flipped = logical(qc.absolute_polarity_flipped);
    end
end

function value = cache_logical(meta, name)
% CACHE_LOGICAL Treat absent optional polarity metadata in old caches as false.

    value = false;
    if isfield(meta, name) && isscalar(meta.(name))
        value = logical(meta.(name));
    end
end
