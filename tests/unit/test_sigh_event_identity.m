function tests = test_sigh_event_identity
% Synthetic breath-identity regressions; no recordings, caches, or review files.
    tests = functiontests(localfunctions);
end

function testRegressionPeaksRemainTwoAutomaticEvents(testCase)
    [data, features, config] = fixture( ...
        [1034;1043.025;1051.385;1058], [1;2;3;1], [], [], 200);
    before = features;
    [events, diagnostics] = detect_sigh(data, features, struct(), config);
    verifyEqual(testCase, [events.start_t], [1043.025 1051.385], 'AbsTol', 1e-12);
    verifyEqual(testCase, [events.start_idx], [events.end_idx]);
    verifyEqual(testCase, [events.duration], [1 1]/200);
    verifyEqual(testCase, {events.belt}, {'lungs','lungs'});
    verifyEqual(testCase, diagnostics.lungs.sigh_flags, [false;true;true;false]);
    verifyEqual(testCase, features, before);
end

function testThreeConsecutiveSighsRemainThree(testCase)
    [data, features, config] = fixture([2;6;10;14;18], [1;2;3;4;1]);
    events = detect_sigh(data, features, struct(), config);
    verifyEqual(testCase, [events.start_t], [6 10 14]);
    verifyEqual(testCase, {events.type}, {'sigh','sigh','sigh'});
end

function testSameBreathFromTwoBeltsCountsOnce(testCase)
    [data, features, config] = fixture([2;6;10], [1;3;1], ...
        [2.2;6.2;10.2], [1;3;1]);
    events = detect_sigh(data, features, struct(), config);
    verifyNumElements(testCase, events, 1);
    verifyEqual(testCase, events.start_t, 6);
    verifyEqual(testCase, events.belt, 'both');
end

function testPairFullBreathTrainsInsteadOfNearestSighs(testCase)
    [data, features, config] = fixture([2;3;4;5], [1;3;1;1], ...
        [2.2;3.2;4.2;5.2], [1;1;3;1]);
    events = detect_sigh(data, features, struct(), config);
    verifyEqual(testCase, [events.start_t], [3 4.2], 'AbsTol', 1e-12);
    verifyEqual(testCase, {events.belt}, {'lungs','diaph'});
end

function testNormalizationNeverJoinsDistinctSighs(testCase)
    points = [peak_event(10,'lungs',10);peak_event(11,'diaph',10)];
    for type = {'sigh','sigh_lungs','sig','sigh-lungs','Sigh Lungs'}
        raw = points; [raw.type] = deal(type{1});
        verifyNumElements(testCase, merge_events({raw}, 100), 2);
        normalized = normalize_event_types_and_meta(raw, 10);
        verifyEqual(testCase, [normalized.start_idx], [10 11]);
        verifyEqual(testCase, [normalized.end_idx], [10 11]);
        verifyNumElements(testCase, normalize_review_events(raw, 10), 2);
    end
    duplicate = normalize_event_types_and_meta( ...
        [peak_event(10,'lungs',10);peak_event(10,'diaph',10)],10);
    verifyNumElements(testCase, duplicate, 1);
    verifyEqual(testCase, duplicate.belt, 'both');
end

function testHistoricalIntervalsSurviveAndOtherLabelsStillMerge(testCase)
    a = normalize_event_types_and_meta(struct('type','sigh', ...
        'start_idx',10,'end_idx',25),10);
    b = normalize_event_types_and_meta(struct('type','sigh', ...
        'start_idx',20,'end_idx',35),10);
    verifyEqual(testCase, normalize_event_types_and_meta([a;b],10), [a;b]);
    verifyEqual(testCase, normalize_review_events([a;b],10), [a;b]);
    verifyEqual(testCase, merge_events({[a;b]}), [a;b]);
    a.type = 'deep'; b.type = 'deep';
    for merged = {merge_events({[a;b]}), normalize_event_types_and_meta([a;b],10)}
        verifyNumElements(testCase, merged{1}, 1);
        verifyEqual(testCase, [merged{1}.start_idx merged{1}.end_idx], [10 35]);
    end
end

function testAutomaticAndReviewedCountsUseEventsNotMaskRuns(testCase)
    config = make_test_config(); config.fs = 1;
    labels = get_labels('short'); N = 1200;
    sets = empty_sets();
    sets.sigh = [peak_event(10,'lungs',1);peak_event(11,'lungs',1);peak_event(12,'lungs',1)];
    sets.irregular = normalize_event_types_and_meta( ...
        struct('type','irregular','start_idx',1,'end_idx',30),1);
    coverage = true(N,numel(labels));
    [reviewed, round] = create_manual_review_round(sets,sets,coverage,config,struct());
    info = struct('reviewed_fields',{{'sigh','irregular'}}, ...
        'review_coverage_mask',coverage,'review_history',round, ...
        'review_provenance',struct('latest_round_id',1));
    annotations = assemble_annotation_layers(sets,reviewed,info,N,config);
    verifyEqual(testCase, annotations.events_automatic, annotations.events_reviewed);
    verifyEqual(testCase, nnz(annotations.mask_automatic(:,strcmp(labels,'sigh'))),3);
    scope = true(N,numel(labels)); scope(901:end,strcmp(labels,'sigh')) = false;
    burden = compute_recording_label_burden(annotations.mask_automatic,labels, ...
        true(size(labels)),annotations.events_automatic,1,scope);
    verifyEqual(testCase, burden.sigh_count, 3);
    verifyEqual(testCase, burden.sighs_per_15_min, 3);
    verifyEqual(testCase, burden.max_sighs_in_any_15_min_window, 3);
    verifyEqual(testCase, burden.median_inter_sigh_interval_sec, 1);
    verifyEqual(testCase, burden.minimum_inter_sigh_interval_sec, 1);
    verifyTrue(testCase, isnan(burden.by_label.sigh.duration_sec));
    overlaps = compute_label_overlap_summary(annotations.mask_automatic,labels, ...
        true(size(labels)),1,scope,annotations.events_automatic);
    verifyEqual(testCase, overlaps.sigh_irregular.assessable_a_event_count,3);
    verifyEqual(testCase, overlaps.sigh_irregular.fraction_of_a_events_with_b_at_midpoint,1);
    phenotype = build_db_phenotype_evidence(burden,overlaps,struct());
    verifyEqual(testCase, phenotype.literature_based.periodic_deep_sighing.signal_derived_measures.sigh_count,3);
end

function testExistingPointAnnotationsKeepTheirActualPanelPeak(testCase)
    [~, features, config] = fixture([2;6;10], [1;3;1], ...
        [2.2;6.2;10.2], [1;3;1]);
    [candidates,~,panels] = build_sigh_breath_candidates(features,200,config.fs);
    original = peak_event(63,'diaph',10);
    [selected, highlighted] = sigh_events_at_peaks(original,candidates,panels,10);
    verifyEqual(testCase, selected, original);
    verifyEqual(testCase, highlighted, [false;true;false]);
    legacy = original; legacy.start_idx = 51; legacy.end_idx = 70;
    legacy.start_t = 5; legacy.end_t = 7; legacy.duration = 2;
    selected = sigh_events_at_peaks(legacy,candidates,panels,10);
    verifyNumElements(testCase, selected,1);
    legacy.end_idx = 110; legacy.end_t = 11; legacy.duration = 6;
    selected = sigh_events_at_peaks(legacy,candidates,panels,10);
    verifyEqual(testCase,[selected.start_idx],[61 101]);
    unmatched = peak_event(180,'diaph',10);
    verifyEqual(testCase,sigh_events_at_peaks(unmatched,candidates,panels,10),unmatched);
end

function testSighOnlyRefreshPreservesActiveReviewAndHistory(testCase)
    config = make_test_config(); config.fs = 10;
    config.execution.selected_labels = {'sigh'};
    N = 4000; data = zeros(N,6); data(:,3) = 98;
    amplitude = ones(100,1); amplitude([5 6 7]) = 3;
    cycles = struct('lungs',belt((2:4:398)',amplitude,10), ...
        'diaph',belt([],[],10));
    reference = struct('session',struct('available',true,'value',1), ...
        'global',struct('available',true,'value',1),'reference_quality','good');
    refs = struct('lungs',reference,'diaph',reference);
    features = compute_respiratory_features(data,cycles,refs,config);
    session = get_session_reference_interval(N,config);
    detections = run_selected_label_detectors(data,features,cycles,refs,session, ...
        config,{'sigh'},struct());
    existing = finalize_selected_label_results(data,features,detections,config,{'sigh'},struct());
    fields = {'available','availability_reason','assessable_mask', ...
        'reviewed_available','reviewed_availability_reason','reviewed_assessable_mask'};
    for i = 1:numel(fields), existing.(['label_' fields{i}]) = existing.(fields{i}); end
    existing.events_reviewed = existing.events_automatic([1 3]);
    existing.mask_reviewed = events_to_time_mask(existing.events_reviewed,N,config);
    row = strcmp(existing.label_names,'sigh');
    existing.review_coverage_mask(:,row) = true;
    existing.review_status(row) = {'reviewed_edited'};
    existing.review_history = struct('round_id',7,'events',existing.events_reviewed, ...
        'notes','Retain accepted and rejected sigh decisions');
    existing.review_provenance = struct('latest_round_id',7);
    existing.manual_label_edit = struct('review_history',existing.review_history, ...
        'review_coverage_mask',existing.review_coverage_mask,'applied_saved_edits',true);
    before = existing;
    refreshed = finalize_selected_label_results(data,features,detections,config,{'sigh'},existing);
    verifyEqual(testCase,numel(refreshed.events_automatic),3);
    verifyEqual(testCase,refreshed.events_reviewed,before.events_reviewed);
    verifyEqual(testCase,refreshed.review_coverage_mask,before.review_coverage_mask);
    verifyEqual(testCase,refreshed.review_history,before.review_history);
    verifyEqual(testCase,refreshed.review_provenance,before.review_provenance);
    verifyEqual(testCase,refreshed.manual_label_edit.review_history,before.review_history);
    verifyEqual(testCase,existing,before);
end

function testComparisonPlotsUseCanonicalAutomaticPeaks(testCase)
    [~, cycles, config] = fixture([2;6;10],[1;3;1],[2.2;6.2;10.2],[1;3;1]);
    config.plot_format = 'fig'; config.LabelMask.do_plot = true;
    file_cleanup = onCleanup(@() delete_comparison_plots(config.sub_results_path)); %#ok<NASGU>
    N = 200; labels = get_labels('short');
    event = peak_event(63,'diaph',10);
    mask = events_to_time_mask(event,N,config);
    result = struct('review_provenance',struct('latest_round_id',1), ...
        'events_automatic',event,'events_reviewed',event,'resp_cycles',cycles, ...
        'mask_automatic',mask,'mask_reviewed',mask,'label_names',{labels}, ...
        'review_coverage_mask',true(size(mask)),'label_assessable_mask',true(size(mask)), ...
        'label_availability_reason',{repmat({'available'},size(labels))});
    before = result;
    plot_reviewed_label_masks(result,config);
    filename = fullfile(config.sub_results_path,'Sub999_M1_label_mask_comparison_round_1.fig');
    fig = openfig(filename,'invisible'); cleanup = onCleanup(@() close(fig)); %#ok<NASGU>
    markers = findall(fig,'Tag','SighEventMarkers');
    verifyNumElements(testCase,markers,2);
    for i = 1:numel(markers)
        verifyEqual(testCase,markers(i).XData,6.2,'AbsTol',1e-12);
    end
    verifyEqual(testCase,nnz(arrayfun(@(h) strcmp(h.MarkerFaceColor,'none'),markers)),1);
    verifyEqual(testCase,result,before);
end

function [data, features, config] = fixture(lungs_t,lungs_a,diaph_t,diaph_a,fs)
    if nargin < 3, diaph_t = []; diaph_a = []; end
    if nargin < 5, fs = 10; end
    config = make_test_config(); config.fs = fs;
    N = max(100,ceil((max([0;lungs_t(:);diaph_t(:)])+2)*fs));
    data = zeros(N,6);
    features = struct('lungs',belt(lungs_t,lungs_a,fs), ...
        'diaph',belt(diaph_t,diaph_a,fs));
end

function delete_comparison_plots(folder)
    for name = {'reviewed','comparison'}
        filename = fullfile(folder,['Sub999_M1_label_mask_' name{1} '_round_1.fig']);
        if isfile(filename), delete(filename); end
    end
    if isfolder(folder), rmdir(folder); end
end

function value = belt(peaks,amplitude,fs)
    peaks = peaks(:); amplitude = amplitude(:);
    troughs = (peaks(1:end-1)+peaks(2:end))/2;
    value = struct('ok',~isempty(peaks),'available',~isempty(peaks),'ignored',false, ...
        'peak_t',peaks,'peak_idx',round(peaks*fs)+1, ...
        'trough_t',troughs,'trough_idx',round(troughs*fs)+1,'amp',amplitude, ...
        'amp_ratio_session',amplitude,'session_reference_value',1, ...
        'session_amplitude_available',~isempty(peaks),'amp_ratio_global',amplitude, ...
        'global_reference_value',1,'global_amplitude_available',~isempty(peaks), ...
        'reference_quality','good');
end

function sets = empty_sets()
    defs = manual_label_definitions(); sets = struct();
    for i = 1:numel(defs), sets.(defs(i).field) = empty_events(); end
end

function event = peak_event(index,belt,fs)
    event = struct('type','sigh','start_idx',index,'end_idx',index, ...
        'start_t',(index-1)/fs,'end_t',index/fs,'duration',1/fs,'belt',belt);
end
