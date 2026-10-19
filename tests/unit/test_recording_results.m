function tests = test_recording_results
    tests = functiontests(localfunctions);
end

function testHierarchyAndScientificRoundTrip(testCase)
    [original,cleanup] = fixture(); %#ok<ASGLU>
    packed = recording_results('pack',original);
    verifyEqual(testCase,fieldnames(packed), ...
        {'metadata';'respiration';'references';'labels';'phenotypes';'review';'qc';'diagnostics';'config'});
    verifyEqual(testCase,packed.metadata.result_schema_version,'magma_recording_results_v1');
    verifySize(testCase,packed.labels.automatic.mask,[100 11]);
    verifyEqual(testCase,packed.phenotypes.automatic.numeric_summary.n_features,24);
    verifyFalse(testCase,isfield(packed.config,'times'));
    verifyFalse(testCase,isfield(packed.review.manual_label_edit,'review_history'));
    verifyFalse(testCase,isfield(packed.qc.respiratory_artifacts,'artifact_intervals_idx'));
    verifyFalse(testCase,isfield(packed.phenotypes.automatic.numeric_summary,'feature_names'));
    schema = get_phenotype_feature_schema();
    verifyEqual(testCase,packed.metadata.phenotype_schema.feature_names,schema.feature_names);
    filename = fullfile(original.config.path_results_out,'synthetic_results.mat');
    recording_results('save',filename,original);
    verifyEqual(testCase,who('-file',filename),{'results'});
    saved = load(filename);
    verifyEqual(testCase,saved.results.labels.automatic.mask,original.mask_automatic);
    actual = recording_results('load',filename);
    scientific = {'resp_cycles','resp_features','resp_ref','session_reference','spo2_ref', ...
        'events_automatic','events_reviewed','mask_automatic','mask_reviewed', ...
        'label_assessable_mask','label_reviewed_assessable_mask','review_coverage_mask', ...
        'label_burden_automatic','label_burden_reviewed','label_overlap_summary_automatic', ...
        'label_overlap_summary_reviewed','label_evidence_summary_automatic', ...
        'label_evidence_summary_reviewed','detector_diagnostics','phenotypes', ...
        'review_history','review_provenance','recording_observations', ...
        'analysis_recording_observations','respiratory_artifact_state'};
    for k = 1:numel(scientific)
        verifyTrue(testCase,isequaln(actual.(scientific{k}),original.(scientific{k})),scientific{k});
    end
    verifyEqual(testCase,actual.manual_label_edit.review_history,original.review_history);
end

function testMetadataUpdatesStayNestedAndNoOpDoesNotRewrite(testCase)
    [original,cleanup] = fixture(); %#ok<ASGLU>
    filename = fullfile(original.config.path_results_out,'synthetic_results.mat');
    recording_results('save',filename,original);
    before = read_bytes(filename);
    changed = recording_results('update',filename,struct('recording_observations',original.recording_observations));
    verifyFalse(testCase,changed); verifyEqual(testCase,read_bytes(filename),before);
    observation = original.recording_observations;
    observation.status = 'observed'; observation.revision = 1; observation.pending_reanalysis = true;
    changed = recording_results('update',filename,struct('recording_observations',observation));
    verifyTrue(testCase,changed); verifyEqual(testCase,who('-file',filename),{'results'});
    actual = recording_results('load',filename);
    verifyEqual(testCase,actual.mask_automatic,original.mask_automatic);
    verifyEqual(testCase,actual.review_history,original.review_history);
    verifyEqual(testCase,actual.resp_cycles,original.resp_cycles);
    saved = load(filename); verifyTrue(testCase,saved.results.qc.pending_reanalysis);
    verifyEqual(testCase,actual.analysis_recording_observations,original.analysis_recording_observations);
    contents = dir(original.config.path_results_out);
    verifyEqual(testCase,{contents(~[contents.isdir]).name},{'synthetic_results.mat'});
end

function testObsoleteResultsAndTwentyTwoFeatureVectorsAreRejected(testCase)
    [original,cleanup] = fixture(); %#ok<ASGLU>
    filename = fullfile(original.config.path_results_out,'obsolete.mat');
    save(filename,'-struct','original');
    verifyError(testCase,@() recording_results('load',filename),'MAGMA:Results:ObsoleteSchema');
    config = original.config; config.overwrite_results = true; config.overwrite_features = false;
    old = warning('off','MAGMA:Results:Regenerate');
    restore_warning = onCleanup(@() warning(old)); %#ok<NASGU>
    verifyEmpty(testCase,fieldnames(recording_results('existing',filename,config)));
    config.execution.mode = 'review_only';
    verifyError(testCase,@() recording_results('existing',filename,config),'MAGMA:Results:ObsoleteSchema');
    original.phenotypes.automatic.numeric_summary.n_features = 22;
    verifyError(testCase,@() recording_results('pack',original),'MAGMA:PhenotypeFeatures:InvalidCompactFeatures');
end

function testHdf5ScientificExportMatchesReopenedMat(testCase)
    [original,cleanup] = fixture(); %#ok<ASGLU>
    filename = fullfile(original.config.path_results_out,'synthetic_results.mat');
    recording_results('save',filename,original);
    actual = recording_results('load',filename);
    signals = ones(100,6); signals(:,3) = 98;
    direct = fullfile(original.config.path_results_out,'direct.h5');
    reopened = fullfile(original.config.path_results_out,'reopened.h5');
    export_results_hdf5(direct,original,signals,signals);
    export_results_hdf5(reopened,actual,signals,signals);
    paths = {'/labels/automatic/mask','/labels/reviewed/coverage_mask', ...
        '/labels/automatic/assessable_mask','/phenotypes/automatic/numeric_summary/values', ...
        '/phenotypes/reviewed/numeric_summary/values','/breaths/artifact_intervals_idx', ...
        '/review/history/round_000001/review_mask','/signals/ml/respiratory_artifact_valid_mask'};
    for k = 1:numel(paths), verifyTrue(testCase,isequaln(h5read(direct,paths{k}),h5read(reopened,paths{k})),paths{k}); end
    verifyEqual(testCase,read_hdf5_text(reopened,'/meta/export_schema_version'),{'magma_ml_hdf5_v19'});
end

function testConfigurationKeepsAnalysisSnapshotsSeparateFromCurrentAnnotations(testCase)
    [original,cleanup] = fixture(); %#ok<ASGLU>
    original.config.recording_observations = original.analysis_recording_observations;
    original.config.respiratory_artifact_state = original.resp_features.respiratory_artifact_state;
    original.recording_observations.status = 'observed'; original.recording_observations.revision = 1;
    original.respiratory_artifact_state.revision = 3;
    packed = recording_results('pack',original);
    verifyFalse(testCase,isfield(packed.config,'recording_observations'));
    verifyFalse(testCase,isfield(packed.config,'respiratory_artifact_state'));
    actual = recording_results('unpack',packed);
    verifyEqual(testCase,actual.config.recording_observations,original.analysis_recording_observations);
    verifyEqual(testCase,actual.config.respiratory_artifact_state,original.resp_features.respiratory_artifact_state);
    verifyNotEqual(testCase,actual.config.respiratory_artifact_state.revision,actual.respiratory_artifact_state.revision);
    original.config.recording_observations.annotation_source = 'distinct_analysis_provenance';
    original.config.respiratory_artifact_state.annotation_source = 'distinct_analysis_provenance';
    actual = recording_results('unpack',recording_results('pack',original));
    verifyEqual(testCase,actual.config.recording_observations,original.config.recording_observations);
    verifyEqual(testCase,actual.config.respiratory_artifact_state,original.config.respiratory_artifact_state);
end

function [result,cleanup] = fixture()
    folder = tempname; mkdir(folder); cleanup = onCleanup(@() rmdir(folder,'s'));
    config = make_test_config(folder); config.fs = 20; config.times = (0:99)'/config.fs;
    config.execution.analysis_id = 'synthetic_analysis';
    names = get_labels('short'); N = 100;
    belt = struct('peak_idx',[5;45;85],'trough_idx',[25;65], ...
        'trough_overrides',[5 45 24],'amp_method','expiratory','orientation','reviewed');
    cycles = struct('lungs',belt,'diaph',belt,'artifact_intervals_idx',[31 35], ...
        'provenance',struct('manual_review_performed',true,'review_status','manual_reviewed_edited'));
    state = respiratory_artifact_state(cycles,config,N); state.revision = 2;
    observation = recording_observation('default',config);
    result = struct('subject',999,'measure',1,'analysis_id','synthetic_analysis', ...
        'config',config,'resp_cycles',cycles,'resp_features',struct('time_sec',(0:4)', ...
        'respiratory_artifact_state',state),'resp_ref',struct('lungs',struct('reference_quality','good'), ...
        'diaph',struct('reference_quality','good')),'spo2_ref',struct('available',false), ...
        'session_reference',get_session_reference_interval(N,config), ...
        'label_names',{names},'label_available',true(1,11), ...
        'label_availability_reason',{repmat({'available'},1,11)}, ...
        'label_reviewed_available',true(1,11), ...
        'label_reviewed_availability_reason',{repmat({'available'},1,11)}, ...
        'mask_automatic',false(N,11),'mask_reviewed',false(N,11), ...
        'label_assessable_mask',true(N,11),'label_reviewed_assessable_mask',true(N,11), ...
        'review_coverage_mask',true(N,11),'review_status',{repmat({'reviewed_unchanged'},1,11)}, ...
        'review_scope','explicitly_viewed_or_edited_regions_per_label', ...
        'events_automatic',empty_events(),'events_reviewed',empty_events(), ...
        'label_burden_automatic',struct(),'label_burden_reviewed',struct(), ...
        'label_overlap_summary_automatic',struct(),'label_overlap_summary_reviewed',struct(), ...
        'label_evidence_summary_automatic',struct(),'label_evidence_summary_reviewed',struct(), ...
        'detector_diagnostics',struct('preserved',[NaN 4 7]), ...
        'recording_observations',observation,'analysis_recording_observations',observation, ...
        'respiratory_artifact_state',state,'analysis_respiratory_artifact_revision',2, ...
        'upstream_input_preprocessing','synthetic');
    result.label_assessable_mask(31:35,1:10) = false;
    result.events_automatic = normalize_event_types_and_meta(result.events_automatic,config.fs);
    result.events_reviewed = normalize_event_types_and_meta(result.events_reviewed,config.fs);
    result.label_reviewed_assessable_mask = result.label_assessable_mask;
    for k=1:numel(names), result.candidate_events.(names{k}) = empty_candidate_events(); end
    result.phenotypes = build_db_phenotype_evidence_bundle(struct(),struct(),struct(),struct(),struct(),struct());
    defs = manual_label_definitions(); sets = struct();
    for k=1:numel(defs), sets.(defs(k).field) = empty_events(); end
    [~,round] = create_manual_review_round(sets,sets,true(N,11),config,struct('round_id',1));
    round.phenotypes_reviewed = result.phenotypes.reviewed;
    round.phenotype_numeric_summary_reviewed = result.phenotypes.reviewed.numeric_summary;
    result.review_history = round;
    result.review_provenance = struct('latest_round_id',1);
    result.manual_label_edit = struct('review_history',round,'review_coverage_mask',true(N,11), ...
        'recording_observations',observation,'review_provenance',result.review_provenance);
end

function bytes = read_bytes(filename)
    fid = fopen(filename,'rb'); cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
    bytes = fread(fid,Inf,'*uint8');
end
