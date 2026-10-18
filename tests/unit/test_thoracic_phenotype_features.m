function tests = test_thoracic_phenotype_features
    tests = functiontests(localfunctions);
end

function testIndependentClinicianValuesAndRhythmicity(testCase)
    [config,data,cycles,cleanup] = fixture(); %#ok<ASGLU>
    qc = compute_thoracic_respiratory_rhythmicity(data,cycles,config);
    verifyTrue(testCase,qc.available); verifyGreaterThan(testCase,qc.thoracic_respiratory_rhythmicity,0.95);
    context.respiratory_signal_qc.thoracic = qc;
    observation = recording_observation('default',config);
    for status = {'not_assessed','not_observed','observed'}
        observation.status = status{1}; context.recording_observations = observation;
        group = build_thoracic_excursion_phenotype(context);
        verifyEqual(testCase,group.values(1),qc.thoracic_respiratory_rhythmicity);
        if strcmp(status{1},'not_assessed')
            verifyTrue(testCase,isnan(group.values(2))); verifyFalse(testCase,group.available(2));
        else
            verifyEqual(testCase,group.values(2),double(strcmp(status{1},'observed')));
            verifyTrue(testCase,group.available(2));
        end
    end
    context.respiratory_signal_qc.thoracic.thoracic_respiratory_rhythmicity = 0;
    group = build_thoracic_excursion_phenotype(context);
    verifyEqual(testCase,group.values(1),0); verifyTrue(testCase,group.available(1));
end

function testSpectralReferenceScaleNoiseAndTechnicalMissingness(testCase)
    [config,data,cycles,cleanup] = fixture(); %#ok<ASGLU>
    original = data; before = cycles;
    data(:,4) = 1e-9*data(:,4);
    tiny = compute_thoracic_respiratory_rhythmicity(data,cycles,config);
    verifyTrue(testCase,tiny.available); verifyGreaterThan(testCase,tiny.thoracic_respiratory_rhythmicity,0.95);
    t = (0:size(data,1)-1)'/config.fs; data(:,4) = sin(2*pi*t);
    other = compute_thoracic_respiratory_rhythmicity(data,cycles,config);
    verifyLessThan(testCase,other.thoracic_respiratory_rhythmicity,0.02);
    rng(7); data(:,4) = randn(size(t));
    noise = compute_thoracic_respiratory_rhythmicity(data,cycles,config);
    verifyLessThan(testCase,noise.thoracic_respiratory_rhythmicity,0.3);
    config.problems.missing_lung_belt = [config.subject config.measure];
    missing = compute_thoracic_respiratory_rhythmicity(original,cycles,config);
    verifyFalse(testCase,missing.available); verifyTrue(testCase,isnan(missing.thoracic_respiratory_rhythmicity));
    verifyEqual(testCase,missing.missing_reason,'thoracic_belt_technically_missing');
    verifyEqual(testCase,cycles,before);
end

function testFlatlineArtifactsGapsAndInsufficientReferenceAreExplicit(testCase)
    [config,data,cycles,cleanup] = fixture(); %#ok<ASGLU>
    flat = data; flat(:,4) = 0;
    qc = compute_thoracic_respiratory_rhythmicity(flat,cycles,config);
    verifyEqual(testCase,qc.missing_reason,'thoracic_flatline');
    artifact = data; artifact([1000 2500 4000],4) = 1e6;
    qc = compute_thoracic_respiratory_rhythmicity(artifact,cycles,config);
    verifyEqual(testCase,qc.missing_reason,'thoracic_transient_artifact');
    gaps = data; gaps(:,4) = NaN;
    qc = compute_thoracic_respiratory_rhythmicity(gaps,cycles,config);
    verifyEqual(testCase,qc.missing_reason,'thoracic_insufficient_finite_coverage');
    cycles.diaph.peak_idx = [];
    qc = compute_thoracic_respiratory_rhythmicity(data,cycles,config);
    verifyEqual(testCase,qc.missing_reason,'insufficient_abdominal_reference');
end

function testLegacySummaryAndAutomaticSnapshotRemainIndependent(testCase)
    [config,data,cycles,cleanup] = fixture(); %#ok<ASGLU>
    bundle = build_db_phenotype_evidence_bundle(struct(),struct(),struct(),struct(),struct(),struct());
    legacy = legacy_summary(bundle.automatic.numeric_summary);
    validate_compact_phenotype_features(legacy);
    aligned = align_phenotype_numeric_summary(legacy);
    verifyEqual(testCase,aligned.n_features,24); verifyTrue(testCase,all(isnan(aligned.values(23:24))));
    history = struct('round_id',1,'phenotype_numeric_summary_reviewed',legacy);
    before_history = history;
    context.respiratory_signal_qc.thoracic = compute_thoracic_respiratory_rhythmicity(data,cycles,config);
    context.analysis_recording_observations = recording_observation('default',config);
    context.recording_observations = context.analysis_recording_observations;
    context.recording_observations.status = 'observed'; context.recording_observations.revision = 1;
    attached = attach_thoracic_excursion_phenotype(bundle,context);
    verifyTrue(testCase,isnan(attached.automatic.numeric_summary.values(24)));
    verifyEqual(testCase,attached.reviewed.numeric_summary.values(24),1);
    verifyEqual(testCase,attached.automatic.numeric_summary.values(23),attached.reviewed.numeric_summary.values(23));
    verifyEqual(testCase,history,before_history);
    config.plot_format = 'fig'; config.PhenotypeSummary.do_plot = true;
    context.recording_observations.pending_reanalysis = true;
    plot_phenotype_summary(attached,config,history,context);
    fig = openfig(fullfile(config.sub_results_path,'Sub999_M1_phenotype_summary.fig'),'invisible');
    cleanup_fig = onCleanup(@() close(fig)); %#ok<NASGU>
    strings = get(findall(fig,'Type','text'),'String');
    verifyTrue(testCase,any(strcmp(strings,'Minimal or absent thoracic excursion')));
    verifyTrue(testCase,any(strcmp(strings,'Not assessed')));
    verifyTrue(testCase,any(contains(strings,'PENDING REANALYSIS')));
end

function testObservationGatesEvidenceWithoutErasingReviewedLandmarks(testCase)
    [config,data,~,cleanup] = fixture(); %#ok<ASGLU>
    cycles = load_or_extract_respiratory_cycles(data,config);
    cycles = reviewed(cycles,config);
    cache = fullfile(config.sub_results_path,config.sub_features_filename);
    cached = load(cache); cached.resp_cycles = cycles; save(cache,'-struct','cached');
    original = load(cache);
    config.recording_observations = recording_observation('set',config,true,'manual_label_gui',0);
    retained = load_or_extract_respiratory_cycles(data,config);
    verifyEqual(testCase,retained.lungs,cycles.lungs);
    verifyEqual(testCase,retained.diaph,cycles.diaph);
    session = get_session_reference_interval(size(data,1),config);
    reference = compute_respiratory_reference(data,retained,session,config);
    features = compute_respiratory_features(data,retained,reference,config);
    verifyFalse(testCase,features.lungs.available); verifyTrue(testCase,features.diaph.available);
    [~,~,panels] = build_sigh_breath_candidates(retained,size(data,1),config.fs);
    verifyTrue(testCase,all(isnan(panels(:,1))));
    before_qc = load(cache);
    compute_thoracic_respiratory_rhythmicity(data,retained,config);
    verifyEqual(testCase,load(cache),before_qc);
    config.recording_observations = recording_observation('set',config,false, ...
        'manual_label_gui',config.recording_observations.revision);
    restored = load_or_extract_respiratory_cycles(data,config);
    verifyEqual(testCase,restored.lungs,original.resp_cycles.lungs);
    verifyEqual(testCase,restored.diaph,original.resp_cycles.diaph);
    cached = load(cache); cached.feature_cache_meta.fs = 123; save(cache,'-struct','cached');
    verifyError(testCase,@() load_or_extract_respiratory_cycles(data,config), ...
        'MAGMA:Respiration:ReviewedFeatureCacheMismatch');
    cached.feature_cache_meta.fs = config.fs;
    cached.resp_cycles.lungs.trough_idx(1) = cached.resp_cycles.lungs.peak_idx(1);
    save(cache,'-struct','cached'); invalid_before = load(cache);
    verifyError(testCase,@() load_or_extract_respiratory_cycles(data,config), ...
        'MAGMA:Respiration:ReviewedFeatureCacheMismatch');
    verifyEqual(testCase,load(cache),invalid_before);
end

function testLateObservationDoesNotOverwriteSavedSpectralValues(testCase)
    [config,data,cycles,cleanup] = fixture(); %#ok<ASGLU>
    original.respiratory_signal_qc.thoracic = compute_thoracic_respiratory_rhythmicity(data,cycles,config);
    original.recording_observations = recording_observation('default',config);
    original.analysis_recording_observations = original.recording_observations;
    original.phenotypes = build_db_phenotype_evidence_bundle(struct(),struct(),struct(), ...
        struct(),struct(),struct(),original);
    file = fullfile(config.sub_results_path,config.sub_results_filename);
    save(file,'-struct','original');
    recording_observation('set',config,true,'manual_label_gui',0);
    saved = load(file);
    verifyEqual(testCase,saved.respiratory_signal_qc,original.respiratory_signal_qc);
    verifyEqual(testCase,saved.phenotypes,original.phenotypes);
    verifyTrue(testCase,saved.recording_observations.pending_reanalysis);
    verifyEqual(testCase,saved.analysis_recording_observations,original.analysis_recording_observations);
end

function testTwoStateDefaultRequiresAcceptanceAndCancellationRemainsSafe(testCase)
    [config,~,~,cleanup] = fixture(); %#ok<ASGLU>
    before = recording_observation('load',config);
    verifyEqual(testCase,before.status,'not_assessed');
    saved = recording_observation('set',config,false,'respiration_feature_gui',0);
    verifyEqual(testCase,saved.status,'not_observed'); verifyEqual(testCase,saved.revision,1);
    config.problems.missing_lung_belt = [config.subject config.measure];
    verifyError(testCase,@() recording_observation('set',config,true,'manual_label_gui',1), ...
        'MAGMA:Observation:MissingBelt');
end

function testFullSyntheticRerunPreservesBothReviewedBeltsAndBackups(testCase)
    [config,raw,~,cleanup] = fixture(); %#ok<ASGLU>
    root = config.path_results_out;
    config.sub_results_path = fullfile(root,'Sub999_M1'); mkdir(config.sub_results_path);
    config.sub_features_filename = 'Sub999_M1_features.mat';
    config.sub_results_filename = 'Sub999_M1_results.mat';
    [data,config] = preprocess_data(raw,config);
    cycles = reviewed(load_or_extract_respiratory_cycles(data,config),config);
    file = fullfile(config.sub_results_path,config.sub_features_filename);
    cached = load(file); cached.resp_cycles = cycles; save(file,'-struct','cached');
    expected = load(file);
    config.subjects = config.subject; config.measurements = config.measure;
    backup = fullfile(root,'backup');
    manifest = backup_recording_mat_files(config,backup);
    verifyTrue(testCase,all([manifest.verified]));
    verifyEqual(testCase,load(manifest(1).backup),expected);
    input_dir = fullfile(root,'input'); mkdir(input_dir);
    writematrix(raw,fullfile(input_dir,'synthetic.dat'),'Delimiter',' ');
    config.path_data_in = input_dir;
    config.input_filename_pattern = 'synthetic.dat'; config.input.filename_pattern = 'synthetic.dat';
    config.overwrite_results = true; config.overwrite_features = false;
    config.execution.mode = 'analyze'; config.execution.selected_labels = {};
    config.LabelMask.do_plot = false; config.PhenotypeSummary.do_plot = false;
    config.exclude_recordings = [];
    config = rmfield(config,{'sub_results_path','sub_features_filename','sub_results_filename'});
    run_magma(config);
    after = load(file);
    verifyEqual(testCase,after.resp_cycles.lungs,expected.resp_cycles.lungs);
    verifyEqual(testCase,after.resp_cycles.diaph,expected.resp_cycles.diaph);
    result = load(fullfile(root,'Sub999_M1','Sub999_M1_results.mat'));
    verifyEqual(testCase,result.resp_cycles.lungs,cycles.lungs);
    verifyEqual(testCase,result.resp_cycles.diaph,cycles.diaph);
    verifyEqual(testCase,result.phenotypes.automatic.numeric_summary.n_features,24);
    verifyTrue(testCase,result.respiratory_signal_qc.thoracic.available);
end

function testGroupMatricesIncludeNewValuesAndLegacyNaNs(testCase)
    [config,data,cycles,cleanup] = fixture(); %#ok<ASGLU>
    b = build_db_phenotype_evidence_bundle(struct(),struct(),struct(),struct(),struct(),struct());
    ctx.respiratory_signal_qc.thoracic = compute_thoracic_respiratory_rhythmicity(data,cycles,config);
    ctx.recording_observations = recording_observation('default',config);
    ctx.recording_observations.status = 'observed';
    ctx.analysis_recording_observations = ctx.recording_observations;
    phenotypes = attach_thoracic_excursion_phenotype(b,ctx);
    current = fullfile(config.path_results_out,'current.mat'); save(current,'phenotypes');
    phenotypes.automatic.numeric_summary = legacy_summary(phenotypes.automatic.numeric_summary);
    phenotypes.reviewed.numeric_summary = legacy_summary(phenotypes.reviewed.numeric_summary);
    legacy = fullfile(config.path_results_out,'legacy.mat'); save(legacy,'phenotypes');
    group_table = table(["Sub999_M1";"Sub999_M2"],[999;999],[1;2], ...
        ["Unknown";"Unknown"],["new";"old"],string({current;legacy}), ...
        'VariableNames',{'recording_id','subject','measure','subject_group','analysis_id','result_file'});
    tables = build_group_phenotype_tables(group_table);
    verifyEqual(testCase,height(tables.dictionary),24);
    verifyEqual(testCase,tables.summary_automatic.minimal_thoracic_excursion_clinician(1),1);
    verifyTrue(testCase,isnan(tables.summary_automatic.minimal_thoracic_excursion_clinician(2)));
    verifyTrue(testCase,isnan(tables.summary_automatic.thoracic_respiratory_rhythmicity(2)));
end

function value = legacy_summary(value)
    fields = {'feature_names','values','available','coverage_fraction','missing_reason','phenotype_group','feature_role','units'};
    for k = 1:numel(fields), value.(fields{k}) = value.(fields{k})(1:22); end
    value.n_features = 22; value.version = 'magma_phenotype_numeric_summary_v3';
    value.schema_version = 'magma_phenotype_numeric_summary_schema_v3';
end

function cycles = reviewed(cycles,config)
    for name = {'lungs','diaph'}
        b = cycles.(name{1});
        b = set_respiration_trough_override(b,b.peak_idx(2),b.peak_idx(3),b.trough_idx(2)+1,config);
        cycles.(name{1}) = b;
    end
    cycles.provenance.review_status = 'manual_reviewed_edited';
    cycles.provenance.manual_review_performed = true;
    cycles.provenance.manual_edits_made = true;
end

function [config,data,cycles,cleanup] = fixture()
    folder = tempname; mkdir(folder);
    cleanup = onCleanup(@() remove_fixture(folder));
    config = make_test_config(folder); config.fs = 20; config.verbosity = 0;
    config.HDF5.enabled = false; config.resp.smooth_sec = 0;
    config.async.analysis_fs = 10;
    config.reference.pre_start_min = 0; config.reference.pre_end_min = 0.5;
    t = (0:4799)'/config.fs;
    data = zeros(numel(t),6); data(:,3) = 98;
    data(:,4) = sin(2*pi*0.25*t); data(:,6) = sin(2*pi*0.25*t);
    config.sub_features_filename = 'Sub999_M1_features.mat';
    config.sub_results_filename = 'Sub999_M1_results.mat';
    cycles = struct('diaph',struct('peak_idx',(21:80:numel(t))'), ...
        'provenance',struct('review_status','manual_reviewed_edited'));
end

function remove_fixture(folder)
    assert(startsWith(folder,tempdir) && ~strcmp(folder,tempdir));
    rmdir(folder,'s');
end
