function run_magma(base_config)
% RUN_MAGMA Execute full or selected-label MAGMA analysis.
% Empty execution.selected_labels preserves normal full-run/overwrite behavior.
% A non-empty selection runs only those detectors and merges their outputs into
% an existing result when present.

    if ~isfield(base_config, 'execution') || ...
            ~isstruct(base_config.execution)
        base_config.execution = struct();
    end
    selected_labels = resolve_selected_labels(base_config);
    base_config.execution.selected_labels = selected_labels;
    mode = execution_mode(base_config);
    if strcmp(mode, 'review_only') && ~isempty(selected_labels)
        error('MAGMA:Execution:SelectedLabelsReviewOnly', ...
            ['config.execution.selected_labels cannot be used with ' ...
             'execution.mode = review_only.']);
    end

    if ~isfolder(base_config.path_results_out)
        mkdir(base_config.path_results_out);
    end
    config = base_config;
    save(fullfile(base_config.path_results_out, ...
        'analysis_configuration.mat'), 'config');

    for isub = 1:length(base_config.subjects)
        for imeasure = 1:length(base_config.measurements)
            config = base_config;
            config.subject = base_config.subjects(isub);
            config.measure = base_config.measurements(imeasure);

            [data_raw, config, do_analysis] = load_raw_data(config);
            if ~do_analysis
                continue;
            end

            result_file = fullfile( ...
                config.sub_results_path, config.sub_results_filename);
            result_exists = isfile(result_file);
            if strcmp(mode, 'review_only')
                existing_results = load(result_file);
                review_config = config;
                if isfield(existing_results, 'config') && ...
                        isfield(existing_results.config, 'detrend')
                    review_config.detrend = existing_results.config.detrend;
                end
                review_config.detrend.do_plot = false;
                [data, review_config] = preprocess_data(data_raw, review_config);
                config.times = review_config.times;
                results = review_existing_results( ...
                    data, existing_results, config);
                save_recording_results(results, data_raw, data, config);
                log_message(config, 1, ...
                    ['Successfully finished manual review for: Sub %d | ' ...
                     'Measurement: %d'], config.subject, config.measure);
                continue;
            end

            selective = ~isempty(selected_labels);
            existing_results = struct();
            if selective && result_exists
                log_message(config, 1, ...
                    'Selective label rerun for Sub %d | Measurement %d', ...
                    config.subject, config.measure);
                log_message(config, 1, 'Selected labels: %s', ...
                    strjoin(selected_labels, ', '));
                log_message(config, 2, 'Loading existing result...');
                existing_results = load(result_file);
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

            config.execution.analysis_id = create_analysis_id(config);
            config.execution.partial_rerun = selective && result_exists;
            config.execution.updated_labels = selected_labels;

            log_message(config, 2, 'Preprocessing signals...');
            [data, config] = preprocess_data(data_raw, config);

            [resp_cycles, reused_cycles] = reusable_resp_cycles( ...
                existing_results, data, config);
            if reused_cycles
                log_message(config, 2, 'Reusing respiratory cycles...');
            else
                log_message(config, 2, 'Extracting respiratory cycles...');
                resp_cycles = load_or_extract_respiratory_cycles(data, config);
            end

            log_message(config, 2, 'Computing respiratory reference...');
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
            log_message(config, 2, 'Recomputing respiratory evidence...');
            resp_features = compute_respiratory_features( ...
                data, resp_cycles, resp_ref, config);

            detections = run_selected_label_detectors( ...
                data, resp_features, resp_cycles, resp_ref, ...
                session_reference, config, selected_labels, existing_results);

            log_message(config, 2, 'Building final label masks...');
            if selective
                if result_exists
                    log_message(config, 2, 'Preserving non-selected labels...');
                end
                label_results = finalize_selected_label_results( ...
                    data, resp_features, detections, config, ...
                    selected_labels, existing_results);
            else
                label_results = finalize_label_results( ...
                    data, resp_cycles, resp_features, session_reference, ...
                    detections, config);
            end

            plot_label_mask( ...
                label_results.mask_automatic, label_results.label_names, config);

            log_message(config, 2, 'Computing summary measures...');
            results = build_recording_results( ...
                config, resp_cycles, resp_ref, session_reference, ...
                resp_features, label_results);
            if selective && result_exists
                log_message(config, 2, 'Saving merged results...');
            end
            save_recording_results(results, data_raw, data, config);
            log_message(config, 1, ...
                ['Successfully finished label detection for: Sub %d | ' ...
                 'Measurement: %d'], config.subject, config.measure);
            log_message(config, 2, 'Done.');
        end
    end
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
        if polarity_flipped(existing.config) ~= polarity_flipped(config)
            return;
        end
    end
    resp_cycles = existing.resp_cycles;
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

function tf = polarity_flipped(config)
% POLARITY_FLIPPED Read preprocessing polarity provenance safely.

    tf = false;
    if isfield(config, 'preprocessing') && ...
            isstruct(config.preprocessing) && ...
            isfield(config.preprocessing, 'belt_polarity_qc') && ...
            isstruct(config.preprocessing.belt_polarity_qc) && ...
            isfield(config.preprocessing.belt_polarity_qc, 'flipped') && ...
            isscalar(config.preprocessing.belt_polarity_qc.flipped)
        tf = logical(config.preprocessing.belt_polarity_qc.flipped);
    end
end
