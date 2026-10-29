function value = recording_results(action, varargin)
% RECORDING_RESULTS Central boundary between analysis structs and MAT storage.
% pack/unpack translate the current schema only. load returns the analysis API;
% save atomically writes one v7.3 variable, results. update skips unchanged
% patches. existing permits explicitly requested regeneration of obsolete MATs
% without importing any historical result fields; feature caches are separate.
% begin_run resets the in-memory, once-per-recording regeneration log.
    persistent regeneration_reported
    if isempty(regeneration_reported), regeneration_reported = {}; end
    switch action
        case 'begin_run'
            regeneration_reported = {};
            value = [];
        case 'pack'
            value = pack(varargin{1});
        case 'unpack'
            value = unpack(varargin{1});
        case 'load'
            value = read_current(varargin{1});
        case 'existing'
            filename = varargin{1}; config = varargin{2};
            current = current_variable(filename);
            if current
                saved = load(filename,'results');
                current = isfield(saved.results,'metadata') && ...
                    isfield(saved.results.metadata,'result_schema_version') && ...
                    strcmp(saved.results.metadata.result_schema_version,'magma_recording_results_v1');
            end
            if current
                value = unpack(saved.results);
            elseif regeneration_allowed(config)
                if ~ismember(filename, regeneration_reported)
                    if isfield(config,'overwrite_features') && config.overwrite_features
                        log_message(config, 1, ...
                            'Regenerating old-format results with fresh respiratory features: Sub%d_M%d', ...
                            config.subject, config.measure);
                    else
                        log_message(config, 1, ...
                            'Regenerating old-format results from saved feature cache: Sub%d_M%d', ...
                            config.subject, config.measure);
                    end
                    regeneration_reported{end+1} = filename;
                end
                value = struct();
            else
                obsolete_result(filename);
            end
        case 'save'
            payload = struct('results',pack(varargin{2}));
            atomic_save_mat(varargin{1},payload,'-v7.3');
            value = [];
        case 'update'
            filename = varargin{1}; patch = varargin{2};
            if numel(varargin) >= 3, internal = varargin{3};
            else, internal = read_current(filename); end
            fields = fieldnames(patch); value = false;
            for k = 1:numel(fields)
                name = fields{k};
                if ~isfield(internal,name) || ~isequaln(internal.(name),patch.(name))
                    internal.(name) = patch.(name); value = true;
                end
            end
            if value, recording_results('save',filename,internal); end
        otherwise
            error('MAGMA:Results:Action','Unknown result-storage action: %s',action);
    end
end

function stored = pack(internal)
    branches = {'metadata','respiration','references','labels','phenotypes', ...
        'review','qc','diagnostics','config'};
    stored = struct();
    for k = 1:numel(branches), stored.(branches{k}) = struct(); end
    fields = field_map();
    unknown = setdiff(fieldnames(internal),fields(:,1));
    if ~isempty(unknown)
        error('MAGMA:Results:UnmappedFields','Add result fields to the centralized storage mapping before saving: %s',strjoin(unknown,', '));
    end
    for k = 1:size(fields,1)
        if isfield(internal,fields{k,1})
            parts = strsplit(fields{k,2},'.');
            stored = setfield(stored,parts{:},internal.(fields{k,1})); %#ok<SFLD>
        end
    end
    stored.metadata.result_schema_version = 'magma_recording_results_v1';
    stored.metadata.n_samples = 0;
    if isfield(internal,'mask_automatic'), stored.metadata.n_samples = size(internal.mask_automatic,1); end
    validate_mask_shapes(internal,stored.metadata.n_samples);
    if isfield(stored.config,'fs'), stored.metadata.fs = stored.config.fs; end
    schema = get_phenotype_feature_schema();
    stored.metadata.phenotype_schema = rmfield(schema,{'display_name','source_description','feature_scope'});
    if isfield(stored.labels,'names') && ~isequal(stored.labels.names,get_labels('short'))
        error('MAGMA:Results:LabelSchema','Results require the current canonical 11-label order.');
    end
    stored.phenotypes = phenotype_summaries(stored.phenotypes,true,schema);
    if isfield(stored.review,'history')
        history = stored.review.history;
        for k = 1:numel(history)
            if isfield(history,'phenotypes_reviewed') && ~isempty(history(k).phenotypes_reviewed)
                if isfield(history,'phenotype_numeric_summary_reviewed') && ...
                        ~isempty(history(k).phenotype_numeric_summary_reviewed) && ...
                        ~isequaln(history(k).phenotype_numeric_summary_reviewed,history(k).phenotypes_reviewed.numeric_summary)
                    error('MAGMA:Results:ReviewSnapshotMismatch','Review round %d has inconsistent phenotype snapshots.',history(k).round_id);
                end
                history(k).phenotypes_reviewed = compact_layer(history(k).phenotypes_reviewed,schema);
            end
            if isfield(history,'phenotype_numeric_summary_reviewed') && ...
                    ~isempty(history(k).phenotype_numeric_summary_reviewed)
                history(k).phenotype_numeric_summary_reviewed = compact_summary(history(k).phenotype_numeric_summary_reviewed,schema);
            end
        end
        % Each current snapshot already contains its numeric summary.
        if isfield(history,'phenotype_numeric_summary_reviewed') && ...
                all(arrayfun(@(h) isempty(h.phenotype_numeric_summary_reviewed) || ...
                    (isfield(h,'phenotypes_reviewed') && ~isempty(h.phenotypes_reviewed)),history))
            history = rmfield(history,'phenotype_numeric_summary_reviewed');
        end
        stored.review.history = history;
    end
    if isfield(stored.review,'manual_label_edit')
        duplicates = {'review_history','review_provenance','review_coverage_mask', ...
            'recording_observations','review_scope','status_by_label'};
        stored.review.manual_label_edit = remove_fields(stored.review.manual_label_edit,duplicates);
    end
    if isfield(stored.qc,'respiratory_artifacts')
        state = stored.qc.respiratory_artifacts;
        if ~isfield(stored.respiration,'cycles'), stored.respiration.cycles = struct(); end
        if ~isfield(stored.respiration.cycles,'artifact_intervals_idx')
            stored.respiration.cycles.artifact_intervals_idx = shared_respiratory_artifacts(state);
        end
        stored.qc.respiratory_artifacts = remove_fields(state, ...
            {'artifact_intervals_idx','lungs','diaph','lungs_evidence','diaph_evidence'});
    end
    observation_pending = isfield(stored.qc,'recording_observations') && stored.qc.recording_observations.pending_reanalysis;
    artifact_pending = isfield(stored.qc,'respiratory_artifacts') && stored.qc.respiratory_artifacts.pending_reanalysis;
    if isfield(stored.qc,'analysis_artifact_revision') && isfield(stored.qc,'respiratory_artifacts')
        artifact_pending = artifact_pending || stored.qc.analysis_artifact_revision ~= stored.qc.respiratory_artifacts.revision;
    end
    stored.qc.pending_reanalysis = observation_pending || artifact_pending;
    stored.metadata.configuration_views = struct();
    views = {'recording_observations','analysis_recording_observations'; ...
        'recording_observations','recording_observations'; ...
        'respiratory_artifact_state','resp_features.respiratory_artifact_state'; ...
        'respiratory_artifact_state','respiratory_artifact_state'};
    for k = 1:size(views,1)
        name = views{k,1}; [source,found] = read_path(internal,strsplit(views{k,2},'.'));
        if isfield(stored.config,name) && found && isequaln(stored.config.(name),source)
            stored.metadata.configuration_views.(name) = views{k,2};
            stored.config = rmfield(stored.config,name);
        end
    end
    stored.config = remove_fields(stored.config,{'times','subject','measure','fs'});
    if isfield(stored.config,'execution')
        stored.config.execution = remove_fields(stored.config.execution,{'analysis_id'});
    end
end

function internal = unpack(stored)
    if ~isstruct(stored) || ~isfield(stored,'metadata') || ...
            ~isfield(stored.metadata,'result_schema_version') || ...
            ~strcmp(stored.metadata.result_schema_version,'magma_recording_results_v1')
        obsolete_result('results structure');
    end
    schema = get_phenotype_feature_schema();
    if ~isequaln(stored.metadata.phenotype_schema, ...
            rmfield(schema,{'display_name','source_description','feature_scope'}))
        error('MAGMA:Results:PhenotypeSchema','Results require the current 24-feature phenotype schema.');
    end
    internal = struct(); fields = field_map();
    for k = 1:size(fields,1)
        [value,found] = read_path(stored,strsplit(fields{k,2},'.'));
        if found, internal.(fields{k,1}) = value; end
    end
    internal.config.fs = stored.metadata.fs;
    validate_mask_shapes(internal,stored.metadata.n_samples);
    for field = {'subject','measure'}
        if isfield(internal,field{1}), internal.config.(field{1}) = internal.(field{1}); end
    end
    if isfield(internal,'analysis_id'), internal.config.execution.analysis_id = internal.analysis_id; end
    if isfield(internal,'label_names') && ~isequal(internal.label_names,get_labels('short'))
        error('MAGMA:Results:LabelSchema','Results require the current canonical 11-label order.');
    end
    if isfield(internal,'manual_label_edit')
        edit = internal.manual_label_edit;
        duplicates = {'review_history','review_provenance','review_coverage_mask','review_scope','recording_observations'};
        for k = 1:numel(duplicates)
            if isfield(internal,duplicates{k}), edit.(duplicates{k}) = internal.(duplicates{k}); end
        end
        if isfield(internal,'review_status')
            defs = manual_label_definitions(); labels = get_labels('short');
            for k = 1:numel(defs), edit.status_by_label.(defs(k).field) = internal.review_status{strcmp(labels,defs(k).type)}; end
        end
        internal.manual_label_edit = edit;
    end
    if isfield(internal,'respiratory_artifact_state')
        state = internal.respiratory_artifact_state;
        state.artifact_intervals_idx = shared_respiratory_artifacts(internal.resp_cycles,stored.metadata.n_samples);
        state.lungs = state.artifact_intervals_idx; state.diaph = state.artifact_intervals_idx;
        state.lungs_evidence = state.evidence_intervals_idx; state.diaph_evidence = state.evidence_intervals_idx;
        internal.respiratory_artifact_state = state;
    end
    internal.phenotypes = phenotype_summaries(stored.phenotypes,false,schema);
    if isfield(internal,'review_history')
        history = internal.review_history;
        if ~isfield(history, 'phenotype_numeric_summary_reviewed')
            [history.phenotype_numeric_summary_reviewed] = deal([]);
        end
        for k = 1:numel(history)
            if isfield(history,'phenotypes_reviewed') && ~isempty(history(k).phenotypes_reviewed)
                history(k).phenotypes_reviewed = expand_layer(history(k).phenotypes_reviewed,schema);
                history(k).phenotype_numeric_summary_reviewed = history(k).phenotypes_reviewed.numeric_summary;
            elseif isfield(history,'phenotype_numeric_summary_reviewed') && ~isempty(history(k).phenotype_numeric_summary_reviewed)
                history(k).phenotype_numeric_summary_reviewed = expand_summary(history(k).phenotype_numeric_summary_reviewed,schema);
            end
        end
        internal.review_history = history;
        if isfield(internal,'manual_label_edit'), internal.manual_label_edit.review_history = history; end
    end
    views = fieldnames(stored.metadata.configuration_views);
    for k = 1:numel(views)
        internal.config.(views{k}) = read_path(internal,strsplit(stored.metadata.configuration_views.(views{k}),'.'));
    end
end

function fields = field_map()
% One mapping for every reader/writer; flat names are internal APIs only.
    fields = { ...
        'subject','metadata.subject'; 'measure','metadata.measurement'; ...
        'analysis_id','metadata.analysis_id'; ...
        'upstream_input_preprocessing','metadata.input_preprocessing'; ...
        'resp_cycles','respiration.cycles'; 'resp_features','respiration.features'; ...
        'session_reference','references.session'; 'resp_ref','references.respiration'; 'spo2_ref','references.spo2'; ...
        'label_names','labels.names'; 'label_assessability_info','labels.assessability'; ...
        'events_automatic','labels.automatic.events'; 'mask_automatic','labels.automatic.mask'; ...
        'label_available','labels.automatic.available'; 'label_availability_reason','labels.automatic.availability_reason'; ...
        'label_assessable_mask','labels.automatic.assessable_mask'; ...
        'label_burden_automatic','labels.automatic.burden'; 'label_overlap_summary_automatic','labels.automatic.overlap'; ...
        'label_evidence_summary_automatic','labels.automatic.evidence'; ...
        'events_reviewed','labels.reviewed.events'; 'mask_reviewed','labels.reviewed.mask'; ...
        'label_reviewed_available','labels.reviewed.available'; 'label_reviewed_availability_reason','labels.reviewed.availability_reason'; ...
        'label_reviewed_assessable_mask','labels.reviewed.assessable_mask'; 'review_coverage_mask','labels.reviewed.coverage_mask'; ...
        'review_status','labels.reviewed.status'; 'review_scope','labels.reviewed.scope'; ...
        'automatic_acceptance','labels.reviewed.automatic_acceptance'; ...
        'label_burden_reviewed','labels.reviewed.burden'; 'label_overlap_summary_reviewed','labels.reviewed.overlap'; ...
        'label_evidence_summary_reviewed','labels.reviewed.evidence'; 'candidate_events','labels.candidates'; ...
        'phenotypes','phenotypes'; 'review_history','review.history'; ...
        'review_provenance','review.provenance'; 'manual_label_edit','review.manual_label_edit'; ...
        'respiratory_signal_qc','qc.respiratory_signal'; 'respiratory_artifact_state','qc.respiratory_artifacts'; ...
        'respiratory_artifact_qc','qc.artifact_coverage'; 'recording_observations','qc.recording_observations'; ...
        'analysis_recording_observations','qc.analysis_recording_observations'; ...
        'analysis_respiratory_artifact_revision','qc.analysis_artifact_revision'; ...
        'detector_diagnostics','diagnostics.detectors'; 'config','config'};
end

function validate_mask_shapes(internal,N)
    for name = {'mask_automatic','mask_reviewed','label_assessable_mask', ...
            'label_reviewed_assessable_mask','review_coverage_mask'}
        if isfield(internal,name{1}) && ~isequal(size(internal.(name{1})),[N 11])
            error('MAGMA:Results:MaskAlignment','%s must be native-sample by 11 canonical labels.',name{1});
        end
    end
end

function bundle = phenotype_summaries(bundle,packing,schema)
    for name = {'automatic','reviewed'}
        if ~isfield(bundle,name{1}), continue; end
        if packing, bundle.(name{1}) = compact_layer(bundle.(name{1}),schema);
        else, bundle.(name{1}) = expand_layer(bundle.(name{1}),schema); end
    end
end

function layer = compact_layer(layer,schema)
    if isfield(layer,'numeric_summary'), layer.numeric_summary = compact_summary(layer.numeric_summary,schema); end
end

function layer = expand_layer(layer,schema)
    if isfield(layer,'numeric_summary'), layer.numeric_summary = expand_summary(layer.numeric_summary,schema); end
end

function summary = compact_summary(summary,schema)
    validate_compact_phenotype_features(summary);
    summary = remove_fields(summary,{'feature_names','phenotype_group','feature_role','units'});
    if summary.n_features ~= schema.n_features, error('MAGMA:Results:PhenotypeSchema','Expected 24 phenotype features.'); end
end

function summary = expand_summary(summary,schema)
    for name = {'feature_names','phenotype_group','feature_role','units'}, summary.(name{1}) = schema.(name{1}); end
    validate_compact_phenotype_features(summary);
end

function [value,found] = read_path(value,parts)
    found = true;
    for k = 1:numel(parts)
        if ~isfield(value,parts{k}), value = []; found = false; return; end
        value = value.(parts{k});
    end
end

function value = remove_fields(value,names)
    present = intersect(fieldnames(value),names);
    if ~isempty(present), value = rmfield(value,present); end
end

function value = read_current(filename)
    if ~current_variable(filename), obsolete_result(filename); end
    saved = load(filename,'results');
    value = unpack(saved.results);
end

function tf = current_variable(filename)
    names = who('-file',filename);
    tf = isequal(names,{'results'});
end

function tf = regeneration_allowed(config)
% Full result regeneration supports either compatible cached or fresh features.
    tf = strcmp(execution_mode(config),'analyze') && isempty(resolve_selected_labels(config)) && ...
        isfield(config,'overwrite_results') && config.overwrite_results;
end

function obsolete_result(filename)
    error('MAGMA:Results:ObsoleteSchema', ...
        ['Unsupported results schema: %s. Regenerate with execution.mode=''analyze'', ' ...
         'overwrite_results=true and no selected labels. Reuse a compatible reviewed ' ...
         'cache with overwrite_features=false, or explicitly recompute features with ' ...
         'overwrite_features=true and resp.recheck_cached=false.'],filename);
end
