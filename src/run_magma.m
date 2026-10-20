function run_magma(base_config)
% RUN_MAGMA Execute full or selected-label MAGMA analysis.
% Empty execution.selected_labels preserves normal full-run/overwrite behavior.
% A non-empty selection runs only those detectors and merges their outputs into
% an existing result when present.

    excluded_recordings = resolve_excluded_recordings(base_config);
    if ~isfield(base_config, 'execution') || ...
            ~isstruct(base_config.execution)
        base_config.execution = struct();
    end
    selected_labels = resolve_selected_labels(base_config);
    base_config.execution.selected_labels = selected_labels;
    mode = execution_mode(base_config);
    if strcmp(mode, 'review_only') && ~isempty(selected_labels)
        error('MAGMA:Execution:SelectedLabelsReviewOnly', ['config.execution.selected_labels cannot be used with execution.mode = review_only.']);
    end

    if get_config_value(base_config,'resp','recheck_cached',false) && ...
            (~isempty(selected_labels) || (isfield(base_config,'overwrite_features') && base_config.overwrite_features))
        error('MAGMA:Respiration:RecheckConfiguration', 'Cached feature recheck requires selected_labels={} and overwrite_features=false.');
    end
    recording_results('begin_run');
    ensure_output_directory(base_config.path_results_out);

    % Save configs
    config = base_config;
    save(fullfile(base_config.path_results_out, 'analysis_configuration.mat'), 'config');
    
    % Go over all subjects & measurements
    for isub = 1:length(base_config.subjects)
        for imeasure = 1:length(base_config.measurements)
            config = base_config;
            config.subject = base_config.subjects(isub);
            config.measure = base_config.measurements(imeasure);
            stem = sprintf('Sub%d_M%d',config.subject,config.measure);
            config.sub_results_path = fullfile(config.path_results_out,stem);
            config.sub_results_filename = [stem '_results.mat'];
            config.sub_features_filename = [stem '_features.mat'];
            if ismember([config.subject config.measure], excluded_recordings, 'rows')
                log_message(config, 1, 'Skipping excluded recording: Sub %d | Measurement: %d', config.subject, config.measure);
                continue;
            end

            config.respiratory_artifact_state = respiratory_artifact_checkpoint('load',config);
            if config.respiratory_artifact_state.pending_reanalysis && ~isempty(selected_labels)
                error('MAGMA:Respiration:FullReanalysisRequired','Respiratory feature edits require a full analysis; clear selected_labels.');
            end
            config.recording_observations = recording_observation('load', config);
            if config.recording_observations.pending_reanalysis && ~isempty(selected_labels)
                error('MAGMA:Observation:FullReanalysisRequired', ...
                    'Pending thoracic observation requires a full respiratory reanalysis; clear selected_labels.');
            end

            % Load data
            [data_raw, config, do_analysis] = load_raw_data(config);
            if ~do_analysis
                if config.respiratory_artifact_state.pending_reanalysis
                    log_message(config,1,'Pending respiratory feature reanalysis: set overwrite_results=true and clear selected_labels.');
                end
                if config.recording_observations.pending_reanalysis
                    log_message(config, 1, 'Pending thoracic-observation reanalysis: set overwrite_results=true to recompute.');
                end
                continue;
            end

            result_file = fullfile(config.sub_results_path, config.sub_results_filename);
            result_exists = isfile(result_file);
            if strcmp(mode, 'review_only')
                existing_results = recording_results('load',result_file);
                review_config = config;
                if isfield(existing_results, 'config') && ...
                        isfield(existing_results.config, 'detrend')
                    review_config.detrend = existing_results.config.detrend;
                end
                review_config.detrend.do_plot = false;
                [data, review_config, polarity_deferred] = preprocess_recording(data_raw, review_config);
                if polarity_deferred, continue; end
                config.times = review_config.times;
                [results, review_cancelled] = review_existing_results(data, existing_results, config);
                if review_cancelled
                    log_message(config, 1, 'Manual review cancelled; existing results were not saved over.');
                    continue;
                end
                plot_reviewed_label_masks(results, config);
                results = save_recording_results(results, data_raw, data, config);
                plot_phenotype_summary(results.phenotypes, config, results.review_history, results);
                log_message(config, 1, ['Successfully finished manual review for: Sub %d | Measurement: %d'], config.subject, config.measure);
                continue;
            end

            selective = ~isempty(selected_labels);
            existing_results = struct();
            if selective && result_exists
                log_message(config, 1, 'Selective label rerun for Sub %d | Measurement %d', config.subject, config.measure);
                log_message(config, 1, 'Selected labels: %s', strjoin(selected_labels, ', '));
                existing_results = recording_results('load',result_file);
            elseif selective
                log_message(config, 1, ...
                    'Running selected labels for Sub %d | Measurement %d', ...
                    config.subject, config.measure);
                log_message(config, 1, 'Selected labels: %s', ...
                    strjoin(selected_labels, ', '));
            else
                log_message(config, 1, ...
                    'Running full label analysis for Sub %d | Measurement %d', ...
                    config.subject, config.measure);
            end

            if ~selective && result_exists
                existing_results = recording_results('existing',result_file,config);
            end
            config.execution.analysis_id = create_analysis_id(config);
            config.execution.partial_rerun = selective && result_exists;
            config.execution.updated_labels = selected_labels;

            [data, config, polarity_deferred] = preprocess_recording(data_raw, config);
            if polarity_deferred, continue; end

            feature_cancelled = false;
            cache_file = fullfile(config.sub_results_path, config.sub_features_filename);
            if get_config_value(config,'resp','recheck_cached',false) && ~isfile(cache_file)
                error('MAGMA:Respiration:RecheckCacheMissing','Restore the reviewed feature cache before rechecking: %s',cache_file);
            end
            if isfile(cache_file)
                [resp_cycles,feature_cancelled] = load_or_extract_respiratory_cycles(data, config);
            else
                [resp_cycles, reused_cycles] = reusable_resp_cycles(existing_results, data, config);
                if ~reused_cycles
                    if reviewed_cycles(existing_results) && ~config.overwrite_features
                        error('MAGMA:Respiration:ReviewedFeatureCacheMismatch', ...
                            'Saved reviewed cycles are incompatible. Restore their cache; no landmarks were regenerated.');
                    end
                    [resp_cycles,feature_cancelled] = load_or_extract_respiratory_cycles(data, config);
                end
            end

            if feature_cancelled
                log_message(config,1,'Respiratory feature review cancelled; cache unchanged and recording reanalysis skipped.');
                continue;
            end
            config.respiratory_artifact_state = respiratory_artifact_state(resp_cycles,config,size(data,1));
            if selective && config.respiratory_artifact_state.pending_reanalysis
                error('MAGMA:Respiration:FullReanalysisRequired','Respiratory feature edits require full reanalysis.');
            end
            previous_revision = config.recording_observations.revision;
            config.recording_observations = recording_observation('load', config);
            if selective && config.recording_observations.pending_reanalysis
                error('MAGMA:Observation:FullReanalysisRequired', ...
                    'The new thoracic observation requires a full analysis; clear selected_labels and rerun.');
            end
            if config.recording_observations.revision ~= previous_revision
                % A landmark-review annotation also changes polarity evidence.
                % Reapply preprocessing; cache alignment preserves reviewed landmarks.
                requested_overwrite = isfield(config, 'overwrite_features') && config.overwrite_features;
                config.overwrite_features = false; % The just-reviewed cache is already fresh.
                recheck_requested = get_config_value(config,'resp','recheck_cached',false);
                config.resp.recheck_cached = false;
                relative_review = [];
                if strcmp(config.preprocessing.belt_polarity_qc.mode, 'manual')
                    relative_review = config.preprocessing.belt_polarity_qc;
                end
                [data, config, polarity_deferred] = preprocess_recording(data_raw, config, relative_review);
                if polarity_deferred, continue; end
                resp_cycles = load_or_extract_respiratory_cycles(data, config);
                config.overwrite_features = requested_overwrite;
                config.resp.recheck_cached = recheck_requested;
            end
            [resp_cycles, ~] = apply_thoracic_observation(resp_cycles, data, config);
            plot_rhythmicity = ~selective && get_config_value(config,'PhenotypeSummary','do_plot',true);
            signal_qc = struct();
            if plot_rhythmicity
                [signal_qc.thoracic,rhythmicity_diagnostic] = ...
                    compute_thoracic_respiratory_rhythmicity(data, resp_cycles, config);
            else
                signal_qc.thoracic = compute_thoracic_respiratory_rhythmicity(data, resp_cycles, config);
            end
            session_reference = get_session_reference_interval( ...
                size(data, 1), config);
            resp_ref = compute_respiratory_reference( ...
                data, resp_cycles, session_reference, config);
            if ~selective
                plot_session_reference( ...
                    data, resp_cycles, resp_ref, session_reference, config);
            end

            % Always recompute derived evidence from the established cycles.
            % This prevents stale configuration-dependent traces (for example,
            % an old irregularity window) from surviving a selected rerun.
            resp_features = compute_respiratory_features( ...
                data, resp_cycles, resp_ref, config);
            
            log_message(config, 2, 'Detecting labels...');
            detections = run_selected_label_detectors( ...
                data, resp_features, resp_cycles, resp_ref, ...
                session_reference, config, selected_labels, existing_results);

            if selective
                label_results = finalize_selected_label_results( ...
                    data, resp_features, detections, config, ...
                    selected_labels, existing_results);
            else
                label_results = finalize_label_results( ...
                    data, resp_cycles, resp_features, session_reference, ...
                    detections, config);
            end

            if isfield(label_results, 'manual_label_edit') && ...
                    isfield(label_results.manual_label_edit, 'cancelled') && ...
                    label_results.manual_label_edit.cancelled
                log_message(config, 1, 'Manual review cancelled; no new result or review plots saved.');
                continue;
            end
            plot_config = config;
            plot_config.LabelMask.assessable_mask = label_results.assessable_mask;
            plot_label_mask( ...
                label_results.mask_automatic, label_results.label_names, ...
                plot_config, label_results.availability_reason);

            results = build_recording_results( ...
                config, resp_cycles, resp_ref, session_reference, ...
                resp_features, label_results, signal_qc);
            plot_reviewed_label_masks(results, config);
            results = save_recording_results(results, data_raw, data, config);
            plot_phenotype_summary(results.phenotypes, config, results.review_history, results);
            if plot_rhythmicity
                rhythmicity_config = config;
                rhythmicity_config.recording_observations = results.recording_observations;
                plot_thoracic_rhythmicity_diagnostic(data,signal_qc.thoracic, ...
                    rhythmicity_diagnostic,rhythmicity_config);
            end
            log_message(config, 1, ...
                ['Successfully finished label detection for: Sub %d | ' ...
                 'Measurement: %d'], config.subject, config.measure);
        end
    end
end

function [data, config, deferred] = preprocess_recording(data_raw, config, relative_review)
% PREPROCESS_RECORDING Treat an explicit polarity deferral as a recording skip.
    if nargin < 3, relative_review = []; end
    deferred = false;
    data = [];
    try
        [data, config] = preprocess_data(data_raw, config, relative_review);
    catch failure
        if ~strcmp(failure.identifier, 'MAGMA:Respiration:PolarityReviewDeferred')
            rethrow(failure);
        end
        deferred = true;
        log_message(config, 1, ...
            ['Respiratory belt polarity decision deferred; skipping Sub%d_M%d ' ...
             'without saving results or feature caches.'], config.subject, config.measure);
    end
end

function tf = reviewed_cycles(existing)
    tf = isfield(existing,'resp_cycles') && has_reviewed_respiration_landmarks(existing.resp_cycles);
end

function [resp_cycles, reused] = reusable_resp_cycles(existing, data, config)
% REUSABLE_RESP_CYCLES Reuse saved reviewed cycles when timeline/polarity match.

    resp_cycles = struct();
    reused = false;
    if isfield(config, 'overwrite_features') && config.overwrite_features
        return;
    end
    if ~isfield(existing, 'resp_cycles') || ...
            ~isstruct(existing.resp_cycles) || ...
            ~all(isfield(existing.resp_cycles, {'lungs', 'diaph'}))
        return;
    end
    belts = {'lungs', 'diaph'};
    for i = 1:numel(belts)
        belt = existing.resp_cycles.(belts{i});
        if ~isstruct(belt) || ~isfield(belt, 'peak_idx') || ...
                (~isempty(belt.peak_idx) && ...
                 max(belt.peak_idx) > size(data, 1)) || ...
                (isfield(belt, 'x0') && ~isempty(belt.x0) && ...
                 numel(belt.x0) ~= size(data, 1))
            return;
        end
    end
    if isfield(existing, 'config')
        if isfield(existing.config, 'fs') && existing.config.fs ~= config.fs
            return;
        end
        if isfield(existing.config, 'data_columns') && ...
                ~isequal(cellstr(string(existing.config.data_columns)), ...
                    cellstr(string(config.data_columns)))
            return;
        end
        if ~isequal(polarity_state(existing.config), polarity_state(config))
            return;
        end
    end
    legacy_state = struct();
    if isfield(existing,'respiratory_artifact_state'), legacy_state = existing.respiratory_artifact_state; end
    resp_cycles = migrate_respiratory_artifacts(existing.resp_cycles,size(data,1),legacy_state);
    [resp_cycles, amplitude_ok] = select_reused_amplitude( ...
        resp_cycles, existing, config);
    if ~amplitude_ok
        resp_cycles = struct();
        return;
    end
    reused = true;
end

function [resp_cycles, ok] = select_reused_amplitude( ...
    resp_cycles, existing, config)
% SELECT_REUSED_AMPLITUDE Keep reviewed timing and select current amplitudes.

    method = resolve_respiration_amplitude_method(config);
    switch method
        case 'expiratory'
            source_field = 'amp_exp';
        case 'inspiratory'
            source_field = 'amp_insp';
        case 'symmetric'
            source_field = 'amp_sym';
    end
    previous_method = '';
    if isfield(existing, 'config') && isstruct(existing.config)
        previous_method = resolve_respiration_amplitude_method(existing.config);
    end
    ok = true;
    belts = {'lungs', 'diaph'};
    for i = 1:numel(belts)
        belt = resp_cycles.(belts{i});
        if isfield(belt, source_field) && ...
                numel(belt.(source_field)) == numel(belt.peak_idx)
            belt.amp = belt.(source_field)(:);
        elseif ~strcmp(previous_method, method) || ...
                ~isfield(belt, 'amp') || ...
                numel(belt.amp) ~= numel(belt.peak_idx)
            ok = false;
            return;
        end
        resp_cycles.(belts{i}) = belt;
    end
end

function state = polarity_state(config)
% POLARITY_STATE Read relative and absolute preprocessing provenance safely.

    [~, thoracic_flipped, diaphragm_flipped] = respiratory_belt_polarity_state(config);
    state = [thoracic_flipped diaphragm_flipped false false];
    if isfield(config, 'preprocessing') && ...
            isstruct(config.preprocessing) && ...
            isfield(config.preprocessing, 'absolute_polarity_qc') && ...
            isstruct(config.preprocessing.absolute_polarity_qc)
        qc = config.preprocessing.absolute_polarity_qc;
        if isfield(qc, 'absolute_polarity_checked') && ...
                isscalar(qc.absolute_polarity_checked)
            state(3) = logical(qc.absolute_polarity_checked);
        end
        if isfield(qc, 'absolute_polarity_flipped') && ...
                isscalar(qc.absolute_polarity_flipped)
            state(4) = logical(qc.absolute_polarity_flipped);
        end
    end
end
