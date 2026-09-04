function tests = test_stage6_freeze
% Deterministic tests for the frozen Stage-6 annotation/export architecture.
    tests = functiontests(localfunctions);
end

function testCanonicalLabelOrderRemainsFrozen(testCase)
    config = stage6_config();
    verifyEqual(testCase, {config.labels.short}, get_labels('short'));
end

function testRapidConfirmationUsesBreathwiseLocalization(testCase)
    config = stage6_config();
    t = (0:120)';
    endpoint = t == 90;
    state = t >= 30 & t <= 90;
    peak_t = [(0:5:40)'; (42:2:90)'];
    lungs = rate_belt(t, peak_t);
    lungs.rate_rapid_window_bpm(endpoint) = 24;
    lungs.rate_rapid_endpoint_mask = endpoint;
    lungs.rate_rapid_state_mask = state;
    phys = rate_phys(t, lungs);

    [events, boundary] = detect_rapid_breathing(zeros(1210, 6), phys, config);
    verifyNumElements(testCase, events, 1);
    verifyEqual(testCase, boundary.events.candidate_start_t, 30);
    verifyEqual(testCase, events.start_t, 40, 'AbsTol', 1/config.fs);
    verifyLessThan(testCase, events.start_t, 60);
    verifyEqual(testCase, boundary.events.evidence_source, ...
        'breathwise_rr_bpm');
end

function testSlowConfirmationUsesBreathwiseLocalization(testCase)
    config = stage6_config();
    t = (0:130)';
    endpoint = t == 100;
    state = t >= 40 & t <= 100;
    peak_t = [(0:5:40)'; (48:8:120)'];
    lungs = rate_belt(t, peak_t);
    lungs.rate_slow_window_bpm(endpoint) = 8;
    lungs.rate_slow_endpoint_mask = endpoint;
    lungs.rate_slow_state_mask = state;
    phys = rate_phys(t, lungs);

    [events, boundary] = detect_slow_breathing(zeros(1310, 6), phys, config);
    verifyNumElements(testCase, events, 1);
    verifyEqual(testCase, boundary.events.candidate_start_t, 40);
    verifyEqual(testCase, events.start_t, 40, 'AbsTol', 1/config.fs);
    verifyLessThan(testCase, events.start_t, 100);
end

function testShallowAndDeepUseBreathMidpointCells(testCase)
    config = stage6_config();
    t = (0:70)';
    lungs = rate_belt(t, (2:2:34)');
    lungs.session_amplitude_available = true;
    lungs.amp_ratio_session = 0.7 * ones(size(lungs.peak_t));
    lungs.shallow_amplitude_mask = t <= 35;
    lungs.shallow_amplitude_endpoint_mask = t == 35;
    lungs.deep_amplitude_mask = t <= 35;
    lungs.deep_amplitude_endpoint_mask = t == 35;
    diaph = empty_rate_belt(t);
    phys.resp = struct('time_sec', t, 'lungs', lungs, 'diaph', diaph);
    [shallow, shallow_info] = detect_shallow_breathing(zeros(710,6), phys, config);
    lungs.amp_ratio_session(:) = 1.3;
    phys.resp.lungs = lungs;
    [deep, deep_info] = detect_deep_breathing(zeros(710,6), phys, config);
    verifyNotEmpty(testCase, shallow);
    verifyNotEmpty(testCase, deep);
    verifyGreaterThan(testCase, shallow.start_t, 0);
    verifyGreaterThan(testCase, deep.start_t, 0);
    verifyEqual(testCase, shallow_info.events.boundary_method, ...
        'confirmed_window_breath_midpoint_localization');
    verifyEqual(testCase, deep_info.events.boundary_method, ...
        'confirmed_window_breath_midpoint_localization');
    verifyTrue(testCase, all([shallow_info.events.passes_final_min_duration]));
    verifyTrue(testCase, all([deep_info.events.passes_final_min_duration]));
end

function testShortLocalizedRunsRemainQcOnlyForAllFourStates(testCase)
    config = stage6_config();
    t = (0:90)';
    amplitude_candidate_state = t <= 30;
    rate_candidate_state = t <= 60;
    N = 910;

    amplitude_belt = rate_belt(t, (1:2:27)');
    amplitude_belt.session_amplitude_available = true;
    amplitude_belt.amp_ratio_session = 0.70 * ones(size(amplitude_belt.peak_t));
    amplitude_belt.shallow_amplitude_mask = amplitude_candidate_state;
    amplitude_belt.shallow_amplitude_endpoint_mask = t == 30;
    amplitude_belt.deep_amplitude_mask = amplitude_candidate_state;
    amplitude_belt.deep_amplitude_endpoint_mask = t == 30;
    phys = rate_phys(t, amplitude_belt);
    [shallow, shallow_info] = detect_shallow_breathing(zeros(N,6), phys, config);
    amplitude_belt.amp_ratio_session(:) = 1.30;
    phys.resp.lungs = amplitude_belt;
    [deep, deep_info] = detect_deep_breathing(zeros(N,6), phys, config);

    rapid_belt = rate_belt(t, (1:2:29)');
    rapid_belt.rate_rapid_window_bpm(t == 60) = 25;
    rapid_belt.rate_rapid_endpoint_mask = t == 60;
    rapid_belt.rate_rapid_state_mask = rate_candidate_state;
    [rapid, rapid_info] = detect_rapid_breathing( ...
        zeros(N,6), rate_phys(t, rapid_belt), config);

    slow_belt = rate_belt(t, (1:6:25)');
    slow_belt.rate_slow_window_bpm(t == 60) = 8;
    slow_belt.rate_slow_endpoint_mask = t == 60;
    slow_belt.rate_slow_state_mask = rate_candidate_state;
    [slow, slow_info] = detect_slow_breathing( ...
        zeros(N,6), rate_phys(t, slow_belt), config);

    verifyEmpty(testCase, shallow);
    verifyEmpty(testCase, deep);
    verifyEmpty(testCase, slow);
    verifyEmpty(testCase, rapid);
    infos = {shallow_info, deep_info, slow_info, rapid_info};
    for i = 1:numel(infos)
        verifyNotEmpty(testCase, infos{i}.events);
        verifyTrue(testCase, any(infos{i}.localized_state_mask));
        verifyFalse(testCase, any(infos{i}.final_state_mask));
        verifyFalse(testCase, any([infos{i}.events.passes_final_min_duration]));
        verifyEqual(testCase, unique([infos{i}.events.final_min_duration_sec]), 30);
        verifyTrue(testCase, all(strcmp( ...
            {infos{i}.events.rejection_reason}, ...
            'localized_duration_below_minimum')));
    end
end

function testDisconnectedLocalizedRunsAreAllRetainedInQc(testCase)
    fs = 10;
    candidate = make_event_fixture('shallow_breathing_lungs', 0, 60, fs);
    peak_t = (2:2:58)';
    ratio = 0.70 * ones(size(peak_t));
    ratio(peak_t == 36) = 1;
    belt = struct('peak_t', peak_t, 'amp_ratio_session', ratio);
    [events, records, localized] = localize_confirmed_breath_events( ...
        candidate, belt, 610, fs, 'shallow_breathing_lungs', ...
        'amplitude_band', 0.65, 0.80, 30, 30, 'lungs');
    verifyNumElements(testCase, localized, 2);
    verifyNumElements(testCase, records, 2);
    verifyNumElements(testCase, events, 1);
    verifyEqual(testCase, [records.passes_final_min_duration], [true false]);
    verifyGreaterThan(testCase, records(2).localized_duration_sec, 0);
    verifyLessThan(testCase, records(2).localized_duration_sec, 30);
end

function testRapidNearMissPlotIsSavedWithoutFinalEvent(testCase)
    output_dir = tempname;
    mkdir(output_dir);
    cleanup = onCleanup(@() rmdir(output_dir, 's'));
    config = stage6_config();
    config.sub_results_path = output_dir;
    config.rapid.do_plot = true;
    t = (0:90)';
    belt = rate_belt(t, (1:2:29)');
    belt.rate_rapid_window_bpm(t == 60) = 25;
    belt.rate_rapid_endpoint_mask = t == 60;
    belt.rate_rapid_state_mask = t <= 60;
    events = detect_rapid_breathing(zeros(910,6), rate_phys(t,belt), config);
    verifyEmpty(testCase, events);
    verifyTrue(testCase, isfile(fullfile(output_dir, ...
        'Sub999_M1_rapid_breathing.png')));

    fig = figure('Visible', 'off');
    cleanup_figure = onCleanup(@() close(fig));
    ax = axes(fig);
    plot(ax, t, zeros(size(t)));
    hold(ax, 'on');
    shade_state_support_on_axis(ax, t, t <= 60, t <= 28, false(size(t)));
    names = string(get(findall(ax, 'Type', 'patch'), 'DisplayName'));
    verifyTrue(testCase, any(names == "Rolling/candidate support"));
    verifyTrue(testCase, any(names == "All localized qualifying support"));
    verifyTrue(testCase, any(names == "Final retained state"));
end

function testThoracicDominanceRetainsExplicitUncertainty(testCase)
    config = stage6_config();
    t = (0:70)';
    state = t >= 10 & t <= 40;
    evidence = struct('available', true, 'analysis_window_sec', 30, ...
        'dominance_endpoint_mask', t == 40, ...
        'dominance_state_mask', state, 'dominance_mask', state);
    phys.resp = struct('time_sec', t, 'thoracoabdominal_balance', evidence);
    [events, info] = detect_thoracic_dominant_breathing(zeros(710,6), phys, config);
    verifyNotEmpty(testCase, events);
    verifyEqual(testCase, info.boundary_uncertainty_sec, 30);
    verifyTrue(testCase, contains(info.boundary_method, 'explicit_uncertainty'));
end

function testIrregularityRetainsWindowScaleUncertainty(testCase)
    config = stage6_config();
    t = (0:100)';
    lungs = empty_rate_belt(t);
    lungs.available = true;
    lungs.irregularity.window_mask(t <= 60) = true;
    lungs.irregularity.endpoint_mask(t == 60) = true;
    lungs.irregularity.cov(t == 60) = 0.4;
    phys.resp = struct('time_sec', t, 'lungs', lungs, ...
        'diaph', empty_rate_belt(t));
    [events, info] = detect_irregular_breathing(zeros(1010,6), phys, config);
    verifyNotEmpty(testCase, events);
    verifyEqual(testCase, info.boundary_uncertainty_sec, 60);
    verifyTrue(testCase, contains(info.boundary_method, 'explicit_uncertainty'));
end

function testApneaRawFlatStoresBoundaryEvidenceSource(testCase)
    config = stage6_config();
    config.apnea.raw_flat_enabled = true;
    config.apnea.do_plot = false;
    t_raw = (0:1/config.fs:400-1/config.fs)';
    data = zeros(numel(t_raw), 6);
    respiratory = sin(2*pi*0.2*t_raw);
    respiratory(t_raw >= 250 & t_raw <= 280) = 0;
    data(:,4) = respiratory;
    data(:,6) = respiratory;
    t = (0:400-1)';
    belt = empty_rate_belt(t);
    belt.available = false;
    belt.session_amplitude_available = false;
    phys.resp = struct('time_sec', t, 'lungs', belt, 'diaph', belt);
    session_reference = get_session_reference_interval(size(data,1), config);
    [events, diagnostics, info] = detect_apnea( ...
        data, phys, session_reference, config);
    verifyNotEmpty(testCase, events);
    verifyTrue(testCase, diagnostics.raw_flat_path_available);
    verifyTrue(testCase, any(strcmp({info.events.evidence_source}, 'raw_flat')));
    native_record = info.events(contains({info.events.boundary_method}, ...
        'raw_flat_native_plateau'));
    verifyNotEmpty(testCase, native_record);
    verifyEqual(testCase, native_record(1).localized_start_t, 250, 'AbsTol', 1/config.fs);
    verifyEqual(testCase, native_record(1).uncertainty_sec, 1/config.fs, ...
        'AbsTol', eps);
end

function testOverlapRejectsMaskColumnMismatch(testCase)
    [mask, names, available] = overlap_fixture();
    verifyError(testCase, @() compute_label_overlap_summary( ...
        mask(:,1:10), names, available, 200), 'MAGMA:Overlap:LabelAlignment');
end

function testOverlapRejectsAvailabilityMismatch(testCase)
    [mask, names, available] = overlap_fixture();
    verifyError(testCase, @() compute_label_overlap_summary( ...
        mask, names, available(1:10), 200), ...
        'MAGMA:Overlap:AvailabilityAlignment');
end

function testOverlapRejectsAssessabilityMismatch(testCase)
    [mask, names, available] = overlap_fixture();
    verifyError(testCase, @() compute_label_overlap_summary( ...
        mask, names, available, 200, false(9,11)), ...
        'MAGMA:Overlap:AssessableMaskSize');
end

function testOverlapRejectsInvalidSamplingRate(testCase)
    [mask, names, available] = overlap_fixture();
    verifyError(testCase, @() compute_label_overlap_summary( ...
        mask, names, available, NaN), 'MAGMA:Overlap:InvalidSamplingRate');
end

function testOverlapRejectsInvalidMaskTypeAndValues(testCase)
    [mask, names, available] = overlap_fixture();
    verifyError(testCase, @() compute_label_overlap_summary( ...
        repmat({'x'},size(mask)), names, available, 200), ...
        'MAGMA:Overlap:InvalidMaskType');
    mask = double(mask); mask(1) = 2;
    verifyError(testCase, @() compute_label_overlap_summary( ...
        mask, names, available, 200), 'MAGMA:Overlap:InvalidMaskValues');
end

function testOverlapRejectsInvalidLabelAndAvailabilityInputs(testCase)
    [mask, names, available] = overlap_fixture();
    verifyError(testCase, @() compute_label_overlap_summary( ...
        mask, 1:numel(names), available, 200), ...
        'MAGMA:Overlap:InvalidLabelNames');
    invalid_available = double(available);
    invalid_available(1) = 2;
    verifyError(testCase, @() compute_label_overlap_summary( ...
        mask, names, invalid_available, 200), ...
        'MAGMA:Overlap:InvalidAvailability');
end

function testOverlapRejectsInvalidAssessabilityTypeAndValues(testCase)
    [mask, names, available] = overlap_fixture();
    verifyError(testCase, @() compute_label_overlap_summary( ...
        mask, names, available, 200, repmat({'x'},size(mask))), ...
        'MAGMA:Overlap:InvalidAssessableMaskType');
    invalid_assessable = double(mask);
    invalid_assessable(1) = NaN;
    verifyError(testCase, @() compute_label_overlap_summary( ...
        mask, names, available, 200, invalid_assessable), ...
        'MAGMA:Overlap:InvalidAssessableMaskValues');
end

function testOverlapRejectsDuplicateAndMissingRequiredLabels(testCase)
    [mask, names, available] = overlap_fixture();
    duplicate = names; duplicate{2} = duplicate{1};
    verifyError(testCase, @() compute_label_overlap_summary( ...
        mask, duplicate, available, 200), ...
        'MAGMA:Overlap:DuplicateLabelNames');
    missing = names; missing{4} = 'notRapid';
    verifyError(testCase, @() compute_label_overlap_summary( ...
        mask, missing, available, 200), ...
        'MAGMA:Overlap:MissingRequiredLabel');
end

function testAutomaticAndReviewedLayersRemainSeparate(testCase)
    config = stage6_config();
    defs = manual_label_definitions();
    automatic = empty_event_sets(defs);
    reviewed = automatic;
    automatic.rapid = make_event_fixture('rapid_breathing_lungs', 10, 20, config.fs);
    coverage = false(300,numel(defs));
    coverage(:,strcmp({defs.field},'rapid')) = true;
    manual = struct('reviewed_fields', {{'rapid'}}, ...
        'status_by_label', struct('rapid', 'reviewed_rejected'), ...
        'review_coverage_mask', coverage);
    sigh = empty_sigh_review();
    annotations = assemble_annotation_layers(automatic, reviewed, manual, sigh, 300, config);
    rapid = strcmp(annotations.label_names, 'rapid');
    shallow = strcmp(annotations.label_names, 'shallow');
    verifyTrue(testCase, any(annotations.mask_automatic(:, rapid)));
    verifyFalse(testCase, any(annotations.mask_reviewed(:, rapid)));
    verifyTrue(testCase, all(annotations.review_coverage_mask(:, rapid)));
    verifyFalse(testCase, any(annotations.review_coverage_mask(:, shallow)));
    verifyEqual(testCase, annotations.review_status{rapid}, 'reviewed_rejected');
end

function testUnreviewedDiffersFromReviewedNegative(testCase)
    config = stage6_config();
    defs = manual_label_definitions();
    automatic = empty_event_sets(defs);
    reviewed = automatic;
    coverage = false(20,numel(defs));
    coverage(:,strcmp({defs.field},'desat')) = true;
    manual = struct('reviewed_fields', {{'desat'}}, ...
        'status_by_label', struct('desat', 'reviewed_accepted'), ...
        'review_coverage_mask', coverage);
    annotations = assemble_annotation_layers( ...
        automatic, reviewed, manual, empty_sigh_review(), 20, config);
    desat = strcmp(annotations.label_names, 'desat');
    apnea = strcmp(annotations.label_names, 'apnea');
    verifyFalse(testCase, any(annotations.mask_reviewed(:, desat)));
    verifyTrue(testCase, all(annotations.review_coverage_mask(:, desat)));
    verifyFalse(testCase, any(annotations.mask_reviewed(:, apnea)));
    verifyFalse(testCase, any(annotations.review_coverage_mask(:, apnea)));
    verifySize(testCase, annotations.review_coverage_mask, [20 11]);
end

function testManualV3CoverageMigratesByLabelIdentity(testCase)
    output_dir = tempname;
    mkdir(output_dir);
    cleanup = onCleanup(@() rmdir(output_dir,'s'));
    config = stage6_config();
    config.sub_results_path = output_dir;
    config.path_results_out = output_dir;
    config.LabelEdit.apply_saved_edits = true;
    config.LabelEdit.manual_control = false;
    defs = manual_label_definitions();
    automatic = empty_event_sets(defs);
    automatic.deep = make_event_fixture('deep_breathing_lungs',10,20,config.fs);
    manual_label_automatic_event_sets = automatic;
    manual_label_event_sets = struct('deepB', empty_events());
    N = 300;
    historical_names = {'shallowB','irregB','slowB','rapidB','asyncB', ...
        'desat','apnea','CSR','deepB','thorDomB'};
    manual_label_review_mask = false(N,numel(historical_names));
    old_deep_index = strcmp(historical_names,'deepB');
    manual_label_review_mask(51:150,old_deep_index) = true;
    manual_label_edit_meta = struct('version',3,'schema_version',3, ...
        'subject',config.subject,'measure',config.measure,'n_samples',N, ...
        'fs',config.fs,'reviewed_fields',{{'deepB'}}, ...
        'label_names',{historical_names});
    filename = fullfile(output_dir,sprintf('Sub%d_M%d%s',config.subject, ...
        config.measure,config.LabelEdit.filename_suffix));
    save(filename,'manual_label_automatic_event_sets','manual_label_event_sets', ...
        'manual_label_review_mask','manual_label_edit_meta');

    [reviewed, info] = manual_edit_label_events(zeros(N,6),config,automatic);
    new_deep_index = strcmp({defs.field},'deep');
    verifyNotEmpty(testCase, automatic.deep);
    verifyEmpty(testCase, reviewed.deep);
    verifyEqual(testCase, info.review_coverage_mask(:,new_deep_index), ...
        manual_label_review_mask(:,old_deep_index));
    verifyEqual(testCase, info.status_by_label.deep,'reviewed_rejected');
    verifyNumElements(testCase, info.review_history, 1);
    verifyEqual(testCase, info.review_history(1).reviewer_role, 'unknown');
    verifyEqual(testCase, info.review_history(1).start_from, 'automatic');
    verifyEqual(testCase, info.review_history(1).review_mask(:, ...
        strcmp({config.labels.short}, 'deep')), ...
        manual_label_review_mask(:,old_deep_index));
end

function testAutomaticSighCandidatesSurviveWithoutReview(testCase)
    config = stage6_config();
    config.sigh.manual_control = false;
    config.sigh.do_plot = false;
    peak_t = (0:4:96)';
    amp = ones(size(peak_t)); amp(12) = 4; amp(end) = NaN;
    belt = struct('peak_t', peak_t, 'amp', amp, ...
        'amp_ratio_global', amp, 'global_reference_value', 1, ...
        'global_amplitude_available', true, 'reference_quality', 'good');
    phys.resp = struct('lungs', belt, 'diaph', belt);
    resp_feat = struct('lungs', belt, 'diaph', belt);
    data = zeros(1000, 6);
    session_reference = get_session_reference_interval(size(data,1), config);
    spo2_ref = struct();
    spo2 = struct();
    [events, diagnostics, review] = detect_sigh( ...
        data, phys, resp_feat, spo2_ref, session_reference, spo2, config);
    verifyNotEmpty(testCase, events);
    verifyEqual(testCase, review.automatic_events, events);
    verifyFalse(testCase, review.reviewed);
    verifyEqual(testCase, diagnostics.lungs.selected_breath_mask, ...
        review.automatic_flags_lungs);
end

function testReviewedSighDoesNotDestroyAutomaticCandidates(testCase)
    config = stage6_config();
    defs = manual_label_definitions();
    automatic = empty_event_sets(defs);
    reviewed = automatic;
    automatic_sigh = make_event_fixture('sigh_lungs',5,7,config.fs);
    sigh = struct('reviewed',true,'review_scope','explicitly_viewed_regions', ...
        'review_mask',true(100,1),'status','reviewed_rejected', ...
        'automatic_events',automatic_sigh,'reviewed_events',empty_events());
    manual = struct('reviewed_fields',{{}},'status_by_label',struct(), ...
        'review_coverage_mask',false(100,numel(defs)));
    annotations = assemble_annotation_layers(automatic,reviewed,manual,sigh,100,config);
    sigh_idx = strcmp(annotations.label_names,'sigh');
    verifyTrue(testCase,any(annotations.mask_automatic(:,sigh_idx)));
    verifyFalse(testCase,any(annotations.mask_reviewed(:,sigh_idx)));
    verifyTrue(testCase,all(annotations.review_coverage_mask(:,sigh_idx)));
end

function testCompleteAndPartialAssessability(testCase)
    config = stage6_config();
    names = {config.labels.short};
    N = 10;
    spo2.valid_sample_mask = true(N,1);
    spo2.valid_sample_mask(4:5) = false;
    rea = struct('time_sec', (0:9)', ...
        'valid_evidence_mask', [false; true(7,1); false; false]);
    [mask, info] = compute_label_assessable_mask( ...
        N, names, true(1,11), spo2, rea, config);
    verifyFalse(testCase, mask(4, strcmp(names,'desat')));
    verifyFalse(testCase, mask(1, strcmp(names,'async')));
    verifyTrue(testCase, all(mask(:, strcmp(names,'rapid'))));
    verifyEqual(testCase, info.version, 'label_assessability_v1');

    unavailable = true(1,11); unavailable(strcmp(names,'thoracic')) = false;
    complete = compute_label_assessable_mask(N, names, unavailable, ...
        struct('valid_sample_mask',true(N,1)), rea, config);
    verifyFalse(testCase, any(complete(:, strcmp(names,'thoracic'))));
end

function testReviewedDesatRequiresAssessableReviewedSamples(testCase)
    config = stage6_config();
    names = {config.labels.short};
    N = 6;
    desat = strcmp(names, 'desat');
    assessable = true(N,11);
    assessable(1:2,desat) = false;
    review = false(N,11);
    review(1:2,desat) = true;
    [reviewed_assessable, reviewed_available, reasons] = ...
        compute_reviewed_label_availability(true(1,11), ...
            repmat({'available'},1,11), assessable, review);
    verifyFalse(testCase, reviewed_available(desat));
    verifyFalse(testCase, any(reviewed_assessable(:,desat)));
    verifyEqual(testCase, reasons{desat}, 'review_scope_unassessable');
    burden = compute_recording_label_burden(false(N,11), names, ...
        reviewed_available, empty_events(), config.fs, reviewed_assessable);
    verifyTrue(testCase, isnan(burden.by_label.desat.duration_sec));
    verifyTrue(testCase, isnan(burden.by_label.desat.fraction));
    overlaps = compute_label_overlap_summary(false(N,11), names, ...
        reviewed_available, config.fs, reviewed_assessable);
    verifyFalse(testCase, overlaps.apnea_desaturation.available);
end

function testReviewedAsyncRequiresValidReviewedReaSamples(testCase)
    config = stage6_config();
    names = {config.labels.short};
    N = 6;
    async = strcmp(names, 'async');
    spo2 = struct('valid_sample_mask', true(N,1));
    rea = struct('time_sec', (0:N-1)', ...
        'valid_evidence_mask', [false; false; true; true; true; true]);
    assessable = compute_label_assessable_mask( ...
        N, names, true(1,11), spo2, rea, config);
    review = false(N,11);
    review(1:2,async) = true;
    [reviewed_assessable, reviewed_available, reasons] = ...
        compute_reviewed_label_availability(true(1,11), ...
            repmat({'available'},1,11), assessable, review);
    verifyFalse(testCase, reviewed_available(async));
    verifyFalse(testCase, any(reviewed_assessable(:,async)));
    verifyEqual(testCase, reasons{async}, 'review_scope_unassessable');
    burden = compute_recording_label_burden(false(N,11), names, ...
        reviewed_available, empty_events(), config.fs, reviewed_assessable);
    verifyTrue(testCase, isnan(burden.by_label.async.fraction));
    overlap = compute_label_overlap_summary(false(N,11), names, ...
        reviewed_available, config.fs, reviewed_assessable);
    [~, ~, label_evidence] = phenotype_fixture();
    phenotypes = build_db_phenotype_evidence( ...
        burden, overlap, label_evidence, 'reviewed_labels');
    verifyFalse(testCase, phenotypes.thoracoabdominal_asynchrony.evidence_available);
    verifyTrue(testCase, isnan(phenotypes.thoracoabdominal_asynchrony. ...
        signal_derived_measures.asynchrony_fraction));
end

function testHalfOpenOneAndMultiSampleEvents(testCase)
    names = get_labels('short');
    fs = 10;
    one_mask = false(10,11);
    one_mask(3,1) = true;
    one = label_mask_to_events(one_mask, names, fs);
    verifyEqual(testCase, one.start_idx, 3);
    verifyEqual(testCase, one.end_idx, 3);
    verifyEqual(testCase, one.start_t, 0.2, 'AbsTol', eps);
    verifyEqual(testCase, one.end_t, 0.3, 'AbsTol', eps);
    verifyEqual(testCase, one.duration, 0.1, 'AbsTol', eps);

    multi_mask = false(10,11);
    multi_mask(3:7,2) = true;
    multi = label_mask_to_events(multi_mask, names, fs);
    verifyEqual(testCase, multi.start_t, 0.2, 'AbsTol', eps);
    verifyEqual(testCase, multi.end_t, 0.7, 'AbsTol', eps);
    verifyEqual(testCase, multi.duration, 0.5, 'AbsTol', eps);
end

function testEventMaskRoundTripsUseIndicesAsAuthority(testCase)
    config = stage6_config();
    config.fs = 10;
    names = {config.labels.short};
    event = struct('type', 'rapid', 'start_idx', 3, 'end_idx', 7, ...
        'start_t', 99, 'end_t', 100, 'duration', 1);
    normalized = normalize_event_types_and_meta(event, config.fs);
    verifyEqual(testCase, normalized.start_t, 0.2, 'AbsTol', eps);
    verifyEqual(testCase, normalized.end_t, 0.7, 'AbsTol', eps);
    verifyEqual(testCase, normalized.duration, 0.5, 'AbsTol', eps);
    mask = events_to_time_mask(normalized, 10, config);
    round_trip = label_mask_to_events(mask, names, config.fs);
    rapid_event = round_trip(strcmp({round_trip.type}, 'rapid'));
    verifyEqual(testCase, rapid_event, normalized);

    original_mask = false(10,11);
    original_mask(2:4,strcmp(names,'shallow')) = true;
    original_mask(8,strcmp(names,'desat')) = true;
    events = label_mask_to_events(original_mask, names, config.fs);
    verifyEqual(testCase, events_to_time_mask(events,10,config), original_mask);
end

function testReviewedBurdenUsesReviewedAssessableDenominator(testCase)
    config = stage6_config();
    names = {config.labels.short};
    mask = false(100,11);
    rapid = strcmp(names,'rapid');
    mask(1:20,rapid) = true;
    review = false(100,11); review(1:40,rapid) = true;
    available = false(1,11); available(rapid) = true;
    burden = compute_recording_label_burden(mask, names, available, ...
        normalize_event_types_and_meta(empty_events()), 10, review);
    verifyEqual(testCase, burden.by_label.rapid.assessable_duration_sec, 4);
    verifyEqual(testCase, burden.by_label.rapid.fraction, 0.5);
    verifyTrue(testCase, isnan(burden.by_label.thoracic.fraction));
end

function testHdf5RoundTripPreservesOrderMasksNaNsAndRespiration(testCase)
    config = stage6_config();
    N = 20;
    results = export_fixture(config, N);
    filename = [tempname '.h5'];
    cleanup = onCleanup(@() delete_if_present(filename));
    raw = reshape(1:N*6, N, 6);
    preprocessed = raw / 10;
    export_results_hdf5(filename, results, raw, preprocessed);

    verifySize(testCase, h5read(filename, '/signals/raw'), [N 6]);
    verifyEqual(testCase, h5read(filename, '/meta/fs'), config.fs);
    verifyEqual(testCase, read_hdf5_text(filename, '/labels/names'), ...
        {config.labels.short});
    verifyEqual(testCase, logical(h5read(filename, '/labels/automatic_mask')), ...
        results.mask_automatic);
    verifyEqual(testCase, logical(h5read(filename, '/labels/reviewed_mask')), ...
        results.mask_reviewed);
    verifyEqual(testCase, logical(h5read(filename, ...
        '/labels/review_coverage_mask')), results.review_coverage_mask);
    verifyTrue(testCase, isnan(h5read(filename, ...
        '/burden/automatic/by_label/desat/fraction')));
    verifyEqual(testCase, logical(h5read(filename, ...
        '/labels/reviewed_assessable_mask')), ...
        results.label_reviewed_assessable_mask);
    verifyEqual(testCase, h5read(filename, '/resp/lungs/peak_idx'), ...
        results.resp_features.resp.lungs.peak_idx);
    verifyEqual(testCase, read_hdf5_text(filename, ...
        '/resp/cycle_provenance/review_status'), {'automatic'});
    verifyEqual(testCase, h5read(filename, '/review/history/number_of_rounds'), 1);
    verifyEqual(testCase, read_hdf5_text(filename, ...
        '/review/history/round_000001/reviewer_role'), {'researcher'});
    verifyEqual(testCase, logical(h5read(filename, ...
        '/review/history/round_000001/review_mask')), ...
        results.review_history(1).review_mask);
    verifyEqual(testCase, logical(h5read(filename, ...
        '/review/history/round_000001/mask')), ...
        results.review_history(1).mask);
    verifyEqual(testCase, h5read(filename, ...
        '/review/provenance/latest_round_id'), 1);
end

function testExternalClinicalPhenotypeValuesRemainUnknown(testCase)
    [burden, overlap, evidence] = phenotype_fixture();
    profiles = build_db_phenotype_evidence( ...
        burden, overlap, evidence, 'reviewed_labels');
    verifyEqual(testCase, profiles.source_provenance, 'reviewed_labels');
    verifyFalse(testCase, profiles.external_clinical_data.Nijmegen_Questionnaire.available);
    verifyEmpty(testCase, profiles.external_clinical_data.Nijmegen_Questionnaire.value);
    verifyFalse(testCase, profiles.hyperventilation_syndrome.assessable_from_current_signals);
    verifyFalse(testCase, profiles.forced_abdominal_expiration.assessable_from_current_signals);
end

function testPhenotypeBundleDistinguishesAnnotationAndDetectorScope(testCase)
    [burden, overlap, evidence] = phenotype_fixture();
    bundle = build_db_phenotype_evidence_bundle( ...
        burden,overlap,evidence,burden,overlap,evidence);
    verifyEqual(testCase,bundle.automatic.source_provenance,'automatic_labels');
    verifyEqual(testCase,bundle.reviewed.source_provenance,'reviewed_labels');
    verifyEqual(testCase,bundle.reviewed.annotation_scope, ...
        'explicitly_reviewed_and_assessable_regions');
    verifyEqual(testCase,bundle.reviewed.detector_evidence_scope, ...
        'full_record_descriptive_evidence_not_manual_confidence');
end

function testNoCompoundLabelColumns(testCase)
    config = stage6_config();
    names = {config.labels.short};
    verifyFalse(testCase, any(contains(names, 'desat_')));
    verifyFalse(testCase, any(contains(names, '_desat')));
    verifyFalse(testCase, any(contains(names, 'rapid_deep')));
    verifyNumElements(testCase, names, 11);
end

function testCohortQcSummarizesAutomaticReviewedAndBeltAvailability(testCase)
    config = stage6_config();
    names = {config.labels.short};
    T = table((1:2)',[1;1], ...
        'VariableNames',{'subject','measure'});
    for i = 1:numel(names)
        token = matlab.lang.makeValidName(names{i});
        T.(['label_' token '_available']) = [1;1];
        T.(['events_' token '_automatic_count']) = [0;2];
        T.(['label_' token '_automatic_fraction']) = [0;0.2];
        T.(['label_' token '_reviewed_coverage_fraction']) = [0;0.5];
        T.(['label_' token '_automatic_reviewed_disagreement_fraction']) = [NaN;0.1];
        T.(['events_' token '_automatic_duration_median_sec']) = [NaN;10];
        T.(['events_' token '_automatic_duration_p90_sec']) = [NaN;15];
    end
    T.respiratory_belt_availability = {'single_belt';'two_belts'};
    T.lungs_reference_quality = {'belt_unavailable';'warning_edge_change'};
    T.diaph_reference_quality = {'good';'good'};
    boundary_qc = table([1;1], [1;1], ["rapid";"rapid"], ...
        [28;20], [false;false], [2;10], ...
        'VariableNames', {'subject','measurement','label', ...
        'localized_duration_sec','passes_final_min_duration', ...
        'duration_shortfall_sec'});
    qc = build_cohort_qc_summary(T,names,table(),boundary_qc);
    verifyEqual(testCase,qc.n_recordings,2);
    verifyEqual(testCase,qc.by_label.automatic_event_count(1),2);
    verifyEqual(testCase,qc.by_label.zero_event_recordings(1),1);
    verifyEqual(testCase,qc.belt_availability.single_belt,1);
    verifyEqual(testCase,qc.belt_availability.two_belts,1);
    verifyEqual(testCase,qc.reference_quality_warning_recordings,1);
    rapid_row = strcmp(qc.by_label.label, 'rapid');
    verifyEqual(testCase,qc.by_label.rejected_localized_run_count(rapid_row),2);
    verifyEqual(testCase,qc.by_label.rejected_localized_duration_max_sec(rapid_row),28);
    verifyEqual(testCase,qc.by_label.rejected_localized_min_shortfall_sec(rapid_row),2);
end

function config = stage6_config()
    config = make_test_config();
    config.fs = 10;
    config.grid_step_sec = 1;
    config.subject = 999;
    config.measure = 1;
    config.problems.missing_lung_belt = zeros(0,2);
    fields = {'shallow','deep','thoracic','irregular','slow','rapid','apnea','sigh'};
    for i = 1:numel(fields)
        config.(fields{i}).do_plot = false;
    end
end

function belt = rate_belt(t, peak_t)
    belt = empty_rate_belt(t);
    belt.available = true;
    belt.peak_t = peak_t(:);
    belt.rr_bpm = 60 ./ diff(belt.peak_t);
end

function belt = empty_rate_belt(t)
    belt = struct('available', false, 'session_amplitude_available', false, ...
        'global_amplitude_available', false, 'ignored', false, ...
        'peak_t', [], 'rr_bpm', [], 'amp_ratio_session', [], ...
        'rate_slow_window_bpm', nan(size(t)), ...
        'rate_rapid_window_bpm', nan(size(t)), ...
        'rate_slow_endpoint_mask', false(size(t)), ...
        'rate_slow_state_mask', false(size(t)), ...
        'rate_rapid_endpoint_mask', false(size(t)), ...
        'rate_rapid_state_mask', false(size(t)), ...
        'shallow_amplitude_mask', false(size(t)), ...
        'shallow_amplitude_endpoint_mask', false(size(t)), ...
        'deep_amplitude_mask', false(size(t)), ...
        'deep_amplitude_endpoint_mask', false(size(t)), ...
        'apnea_amp_ratio_session_window_median', nan(size(t)), ...
        'irregularity', struct('window_mask', false(size(t)), ...
            'endpoint_mask', false(size(t)), 'cov', nan(size(t)), ...
            'robust_cov', nan(size(t)), 'rmssd_sec', nan(size(t)), ...
            'pause_exclusion_mask', false(size(t))));
end

function phys = rate_phys(t, lungs)
    phys.resp = struct('time_sec', t, ...
        'rate_windows_sec', struct('slow',60,'rapid',60), ...
        'lungs', lungs, 'diaph', empty_rate_belt(t));
end

function [mask, names, available] = overlap_fixture()
    config = stage6_config();
    names = {config.labels.short};
    mask = false(10,11);
    available = true(1,11);
end

function sets = empty_event_sets(defs)
    sets = struct();
    for i = 1:numel(defs), sets.(defs(i).field) = empty_events(); end
end

function review = empty_sigh_review()
    review = struct('reviewed', false, 'status', 'unreviewed', ...
        'automatic_events', empty_events(), 'reviewed_events', empty_events());
end

function event = make_event_fixture(type, start_t, end_t, fs)
    event = struct('type', type, 'start_idx', round(start_t*fs)+1, ...
        'end_idx', round(end_t*fs), 'start_t', start_t, 'end_t', end_t, ...
        'duration', end_t-start_t);
end

function results = export_fixture(config, N)
    names = {config.labels.short};
    belt = struct('available', true, 'peak_idx', [1; 11], ...
        'peak_t', [0; 1], 'amp', [1; NaN], 'ibi', 1, 'rr_bpm', 60, ...
        'amp_ratio_session', [1; NaN], 'amp_ratio_global', [1; NaN]);
    results = struct();
    results.subject = 999;
    results.measure = 1;
    results.config = config;
    results.resp_features = struct( ...
        'resp', struct('lungs', belt, 'diaph', belt));
    results.resp_cycles = struct('provenance', struct( ...
        'review_status', 'automatic', ...
        'manual_review_performed', false, ...
        'manual_edits_made', false, ...
        'loaded_from_cache', false));
    results.session_reference = get_session_reference_interval(N, config);
    reference = struct('session', struct('value', 1, 'available', true), ...
        'global', struct('value', 1, 'available', true), ...
        'reference_quality', 'good');
    results.resp_ref = struct('lungs', reference, 'diaph', reference);
    results.spo2_ref = struct('available',false,'quality','test', ...
        'median_percent',NaN,'source','common_session_reference_interval');
    results.label_names = names;
    results.label_available = true(1,11);
    results.label_available(end) = false;
    results.label_availability_reason = repmat({'available'},1,11);
    results.label_availability_reason{end} = 'one_belt_only';
    results.label_assessable_mask = repmat(results.label_available,N,1);
    results.mask_automatic = false(N,11);
    results.mask_automatic(1:3,strcmp(names,'rapid')) = true;
    results.mask_reviewed = false(N,11);
    results.review_coverage_mask = false(N,11);
    results.review_coverage_mask(:,strcmp(names,'rapid')) = true;
    results.review_status = repmat({'unreviewed'},1,11);
    results.review_status{strcmp(names,'rapid')} = 'reviewed_rejected';
    raw_event = make_event_fixture('rapid_breathing_lungs',0,1/config.fs,config.fs);
    results.events_automatic = normalize_event_types_and_meta(raw_event, config.fs);
    results.events_reviewed = normalize_event_types_and_meta(empty_events(), config.fs);
    defs = manual_label_definitions();
    empty_sets = empty_event_sets(defs);
    review_scope = false(N,numel(defs));
    review_scope(:,strcmp({defs.field},'rapid')) = true;
    [~,review_round] = create_manual_review_round(empty_sets,empty_sets, ...
        review_scope,config,struct('round_id',1, ...
        'timestamp','2026-01-01T00:00:00Z','reviewer_role','researcher', ...
        'start_from','automatic','source_review_round',NaN));
    results.review_history = review_round;
    results.review_provenance = struct( ...
        'version','manual_review_provenance_v1','latest_round_id',1, ...
        'latest_reviewer_role','researcher','start_from','automatic', ...
        'source_review_round',NaN,'number_of_rounds',1, ...
        'most_recent_round_id',1);
    results.label_burden_automatic = compute_recording_label_burden( ...
        results.mask_automatic,names,results.label_available,results.events_automatic, ...
        config.fs,results.label_assessable_mask);
    reviewed_available = false(1,11); reviewed_available(strcmp(names,'rapid')) = true;
    reviewed_assessable = results.label_assessable_mask & results.review_coverage_mask;
    results.label_reviewed_available = reviewed_available;
    results.label_reviewed_availability_reason = repmat({'unreviewed'},1,11);
    results.label_reviewed_availability_reason{strcmp(names,'rapid')} = 'available';
    results.label_reviewed_assessable_mask = reviewed_assessable;
    results.label_burden_reviewed = compute_recording_label_burden( ...
        results.mask_reviewed,names,reviewed_available,results.events_reviewed, ...
        config.fs,reviewed_assessable);
    results.label_overlap_summary_automatic = compute_label_overlap_summary( ...
        results.mask_automatic,names,results.label_available,config.fs, ...
        results.label_assessable_mask);
    results.label_overlap_summary_reviewed = compute_label_overlap_summary( ...
        results.mask_reviewed,names,reviewed_available,config.fs, ...
        reviewed_assessable);
    results.db_phenotype_evidence = struct('version','test', ...
        'external_clinical_data',struct('status','not_integrated','value',[]));
    results.upstream_input_preprocessing = 'external / not fully documented';
end

function [burden, overlap, evidence] = phenotype_fixture()
    config = stage6_config();
    names = {config.labels.short};
    mask = false(10,11);
    burden = compute_recording_label_burden(mask,names,true(1,11), ...
        normalize_event_types_and_meta(empty_events()),1);
    overlap = compute_label_overlap_summary(mask,names,true(1,11),1);
    evidence.rapid = struct('median_rr_lungs',NaN,'median_rr_diaph',NaN);
    evidence.deep = struct('median_ratio_lungs',NaN,'median_ratio_diaph',NaN);
    evidence.thoracic = struct('median_ratio',NaN,'median_log_ratio',NaN, ...
        'median_relative_fraction',NaN);
    evidence.async = struct('analysis_valid',false, ...
        'reference_coherence',struct(),'median_observed_coherence',struct(), ...
        'maximum_deviating_bins',NaN);
end

function delete_if_present(filename)
    if isfile(filename), delete(filename); end
end
