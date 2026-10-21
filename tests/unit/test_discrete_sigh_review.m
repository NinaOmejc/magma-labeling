function tests = test_discrete_sigh_review
% Small synthetic regression checks; no recordings or detectors are run.
    tests = functiontests(localfunctions);
end

function testTouchingPeakEventsSurviveRoundAndAssembly(testCase)
    config = make_test_config(); config.fs = 10;
    N = 100; defs = manual_label_definitions(); labels = get_labels('short');
    source = empty_sets(defs); edited = source;
    edited.sigh = [peak_event(10,'lungs',config.fs); peak_event(11,'diaph',config.fs)];
    scope = false(N,numel(defs)); scope(:,strcmp({defs.field},'sigh')) = true;
    [final, round] = create_manual_review_round(source,edited,scope,config,struct());
    verifyEqual(testCase,numel(final.sigh),2);
    verifyEqual(testCase,[final.sigh.start_idx],[10 11]);
    info = struct('reviewed_fields',{{'sigh'}},'review_coverage_mask',scope, ...
        'review_history',round,'review_provenance',struct('latest_round_id',1));
    annotation = assemble_annotation_layers(source,final,info,N,config);
    verifyEqual(testCase,numel(annotation.events_reviewed),2);
    sigh = strcmp(labels,'sigh');
    verifyEqual(testCase,find(annotation.mask_reviewed(:,sigh)),[10;11]);
    burden = compute_recording_label_burden(annotation.mask_reviewed,labels, ...
        true(1,numel(labels)),annotation.events_reviewed,config.fs,annotation.review_coverage_mask);
    verifyEqual(testCase,burden.sigh_count,2);
    verifyEqual(testCase,burden.sighs_per_15_min,180);
    verifyTrue(testCase,isnan(burden.by_label.sigh.duration_sec));
    verifyTrue(testCase,isnan(burden.by_label.sigh.median_event_duration_sec));
end

function testLegacyTouchingBreathsStaySeparate(testCase)
    config = make_test_config(); config.fs = 10;
    defs = manual_label_definitions(); source = empty_sets(defs); edited = source;
    a = peak_event(1,'lungs',config.fs); a.end_idx = 10; a.end_t = 1; a.duration = 1;
    b = peak_event(11,'lungs',config.fs); b.end_idx = 20; b.end_t = 2; b.duration = 1;
    edited.sigh = [a;b]; scope = false(30,numel(defs)); scope(:,strcmp({defs.field},'sigh')) = true;
    [final,round] = create_manual_review_round(source,edited,scope,config,struct());
    verifyEqual(testCase,numel(final.sigh),2);
    verifyEqual(testCase,[final.sigh.start_idx],[1 11]);
    verifyEqual(testCase,nnz(round.mask(:,strcmp(get_labels('short'),'sigh'))),20);
end

function testCoverageChangesOnlyCoveredPeakIdentities(testCase)
    config = make_test_config(); config.fs = 10;
    defs = manual_label_definitions(); source = empty_sets(defs); edited = source;
    source.sigh = peak_event(10,'lungs',config.fs);
    edited.sigh = peak_event(20,'diaph',config.fs);
    scope = false(30,numel(defs)); scope(20,strcmp({defs.field},'sigh')) = true;
    [final,~] = create_manual_review_round(source,edited,scope,config,struct());
    verifyEqual(testCase,[final.sigh.start_idx],[10 20]);
    scope(10,strcmp({defs.field},'sigh')) = true;
    [final,~] = create_manual_review_round(source,edited,scope,config,struct());
    verifyEqual(testCase,[final.sigh.start_idx],20);
end

function testDuplicatePeakCountsOnceWithBothBeltSources(testCase)
    events = normalize_review_events([peak_event(10,'lungs',10);peak_event(10,'diaph',10)],10);
    verifyEqual(testCase,numel(events),1);
    verifyEqual(testCase,events.belt,'both');
    verifyEqual(testCase,fieldnames(events), ...
        {'type';'start_idx';'end_idx';'start_t';'end_t';'duration';'belt'});
end

function testReviewedMaskUsesDotsAndNoSighDurationBlocks(testCase)
    config = make_test_config(); config.fs = 10;
    config.make_figs_visible = 'off'; config.LabelMask.do_plot = true;
    config.plot_format = 'fig';
    plot_file = fullfile(config.sub_results_path,'Sub999_M1_label_mask.fig');
    file_cleanup = onCleanup(@() delete_test_plot(plot_file)); %#ok<NASGU>
    labels = get_labels('short'); row = find(strcmp(labels,'sigh'));
    config.LabelMask.review_coverage = true(30,numel(labels));
    config.LabelMask.review_coverage(21:end,:) = false;
    events = [peak_event(10,'lungs',10);peak_event(11,'diaph',10)];
    mask = events_to_time_mask(events,30,config);
    warning_state = warning('off','all'); warning_cleanup = onCleanup(@() warning(warning_state));
    plot_label_mask(mask,labels,config,[],events,mask,events);
    fig = openfig(plot_file,'invisible'); cleanup = onCleanup(@() close(fig));
    raster = findall(fig,'Type','image');
    verifyEqual(testCase,raster.CData(row,:),[zeros(1,20) 2*ones(1,10)]);
    markers = findall(fig,'Tag','SighEventMarkers');
    verifyEqual(testCase,numel(markers),2);
    for i = 1:numel(markers), verifyEqual(testCase,markers(i).XData,[0.9 1]); end
    verifyEqual(testCase,numel(findall(fig,'Tag','AutomaticDetectionOutline')),0);
end

function testPairedMarkersUseActualPeaksAndOneSharedIdentity(testCase)
    cycles = struct('lungs',struct('peak_t',[1;3],'amp',[1;1],'available',true), ...
        'diaph',struct('peak_t',[1.2;3.1],'amp',[1;1],'available',true));
    [events,peaks,panels] = build_sigh_breath_candidates(cycles,600,100);
    verifyEqual(testCase,peaks,[1;3]);
    verifyEqual(testCase,panels,[1 1.2;3 3.1]);
    verifyEqual(testCase,numel(events),2);
    verifyEqual(testCase,{events.belt},{'both','both'});
    selected = sigh_events_at_peaks(events,events,panels,100);
    verifyEqual(testCase,numel(selected),2);
    legacy = sigh_events_at_peaks(rmfield(events,'belt'),events,panels,100);
    verifyEqual(testCase,[legacy.start_idx],[101 301]);
    cycles.lungs.available = false;
    [events,peaks,panels] = build_sigh_breath_candidates(cycles,600,100);
    verifyEqual(testCase,peaks,[1.2;3.1]);
    verifyTrue(testCase,all(isnan(panels(:,1))));
    verifyEqual(testCase,{events.belt},{'diaph','diaph'});
end

function sets = empty_sets(defs)
    sets = struct();
    for i = 1:numel(defs), sets.(defs(i).field) = empty_events(); end
end

function event = peak_event(index,belt,fs)
    event = struct('type','sigh','start_idx',index,'end_idx',index, ...
        'start_t',(index-1)/fs,'end_t',index/fs,'duration',1/fs,'belt',belt);
end

function delete_test_plot(filename)
    if isfile(filename), delete(filename); end
    folder = fileparts(filename);
    if isfolder(folder), rmdir(folder); end
end
