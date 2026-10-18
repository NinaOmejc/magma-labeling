function tests = test_respiratory_artifacts
% Synthetic signals and temporary files only; GUI callbacks are timer driven.
    tests = functiontests(localfunctions);
end

function testRangesAndIndependentNonDestructiveViews(testCase)
    verifyEqual(testCase,normalize_respiratory_artifacts([20 30;-5 4;5 9;28 45],40),[1 9;20 40]);
    verifyError(testCase,@() normalize_respiratory_artifacts([1.5 3],40),'MAGMA:Respiration:InvalidArtifacts');
    [c,data,cycles,cleanup] = fixture(); %#ok<ASGLU>
    original = cycles; original_data = data;
    left = cycles.lungs.peak_idx(15); right = cycles.lungs.peak_idx(16);
    cycles.lungs.artifact_intervals_idx = [left+3 right-3];
    [view,derived,state] = respiratory_artifact_view(data,cycles,c);
    verifyEqual(testCase,cycles.lungs.peak_idx,original.lungs.peak_idx);
    verifyEqual(testCase,cycles.lungs.trough_overrides,original.lungs.trough_overrides);
    verifyEqual(testCase,data,original_data); verifyEqual(testCase,derived.diaph,cycles.diaph);
    verifyTrue(testCase,isnan(derived.lungs.ibi(15)));
    verifyFalse(testCase,derived.lungs.artifact_valid_ibi_mask(15));
    verifyTrue(testCase,all(isnan(view(left+3:right-3,4))));
    verifyEqual(testCase,view(:,6),data(:,6)); verifyEmpty(testCase,state.diaph);
    good = derived.lungs.artifact_valid_breath_mask;
    verifyEqual(testCase,derived.lungs.amp(good),original.lungs.amp(good));
end

function testEvidenceWindowsReferencesAndAssessability(testCase)
    [c,data,cycles,cleanup] = fixture(); %#ok<ASGLU>
    session = get_session_reference_interval(size(data,1),c);
    ref = compute_respiratory_reference(data,cycles,session,c);
    before = compute_respiratory_features(data,cycles,ref,c);
    cycles.lungs.artifact_intervals_idx = [2201 2601];
    ref2 = compute_respiratory_reference(data,cycles,session,c);
    after = compute_respiratory_features(data,cycles,ref2,c);
    verifyEqual(testCase,after.diaph,before.diaph); verifyEqual(testCase,ref2.diaph,ref.diaph);
    cross = after.time_sec>=110 & after.time_sec<=130+c.slow.analysis_win_sec;
    verifyTrue(testCase,all(isnan(after.lungs.rate_slow_window_bpm(cross))));
    cross = after.time_sec>=110 & after.time_sec<=230;
    verifyTrue(testCase,all(isnan(after.lungs.irregularity.cov(cross))));
    labels = get_labels('short');
    mask = compute_label_assessable_mask(data,labels,true(1,11),struct(),after.time_sec,c,after);
    verifyTrue(testCase,all(mask(2300:2500,1))); % clean abdominal evidence survives
    verifyFalse(testCase,any(mask(2300:2500,9))); % simultaneous two-belt evidence required
    cycles.diaph.artifact_intervals_idx = cycles.lungs.artifact_intervals_idx;
    both = compute_respiratory_features(data,cycles,ref2,c);
    mask = respiratory_artifact_label_mask(both,labels,size(data,1),c);
    verifyFalse(testCase,any(mask(2300:2500,1:10),'all')); verifyTrue(testCase,all(mask(:,11)));
    flat = data; flat(:,6) = 0; cycles.diaph = empty_respiration_feature('diaph'); cycles.diaph.x0 = flat(:,6);
    one = compute_respiratory_features(flat,cycles,ref2,c);
    mask = respiratory_artifact_label_mask(one,labels,size(data,1),c);
    verifyFalse(testCase,any(mask(2300:2500,1:9),'all'));
end

function testApneaFallbackAndSpectralWindowsRejectArtifacts(testCase)
    [c,data,cycles,cleanup] = fixture(); %#ok<ASGLU>
    ref = compute_respiratory_reference(data,cycles,get_session_reference_interval(size(data,1),c),c);
    cycles.lungs.artifact_intervals_idx = [2201 3201]; cycles.diaph.artifact_intervals_idx = [2201 3201];
    features = compute_respiratory_features(data,cycles,ref,c);
    features.lungs.session_amplitude_available = false; features.diaph.session_amplitude_available = false;
    data(2201:3201,[4 6]) = 0;
    [events,diag] = detect_apnea(data,features,ref,c); verifyEmpty(testCase,events);
    cross = features.time_sec>=110 & features.time_sec<=160;
    verifyFalse(testCase,any(diag.raw_excursion.lungs.evaluable_endpoint_mask(cross)));
    qc = compute_thoracic_respiratory_rhythmicity(data,cycles,c);
    verifyFalse(testCase,qc.available); verifyEqual(testCase,qc.missing_reason,'manually_marked_respiratory_artifact');
    c.respiratory_artifact_state = features.respiratory_artifact_state;
    guyot = compute_guyot_periodic_breathing(data,cycles,c);
    inside = guyot.lungs.envelope_t>=110 & guyot.lungs.envelope_t<=160;
    verifyFalse(testCase,any(guyot.lungs.envelope_evaluable_mask(inside)));
    verifyFalse(testCase,any(guyot.lungs.long_gap_mask(inside)));
    eami = compute_eami_periodic_breathing(data,c);
    inside = eami.lungs.t_sec>=110 & eami.lungs.t_sec<=160;
    verifyFalse(testCase,any(eami.lungs.evaluable_mask(inside)));
end

function testArtifactShorterThanAnalysisGridIsStillExcluded(testCase)
    [c,data,cycles,cleanup] = fixture(); %#ok<ASGLU>
    cycles.lungs.artifact_intervals_idx = [2304 2304];
    cycles.diaph.artifact_intervals_idx = [2304 2304];
    c.respiratory_artifact_state = respiratory_artifact_state(cycles,c,size(data,1));
    eami = compute_eami_periodic_breathing(data,c);
    clean = respiratory_artifact_window_valid([2304 2304],eami.lungs.t_sec+30,60,c.fs);
    verifyFalse(testCase,any(eami.lungs.evaluable_mask(~clean)));
    ref = compute_respiratory_reference(data,cycles,get_session_reference_interval(size(data,1),c),c);
    f = compute_respiratory_features(data,cycles,ref,c);
    f.lungs.session_amplitude_available = false; f.diaph.session_amplitude_available = false;
    [~,diag] = detect_apnea(data,f,ref,c);
    clean = respiratory_artifact_window_valid([2304 2304],f.time_sec,c.apnea.min_dur_sec,c.fs);
    verifyFalse(testCase,any(diag.raw_excursion.lungs.evaluable_endpoint_mask(~clean)));
    phase = compute_respiratory_phase_offset_metrics(data,cycles,c);
    verifyEqual(testCase,phase.input_valid_block_count,2);
    near = abs(phase.time_sec-(2304-1)/c.fs)<2;
    verifyFalse(testCase,any(phase.valid_phase_mask(near)));
end

function testLegacyCacheAndCancelAreByteSafe(testCase)
    [c,data,cycles,cleanup] = fixture(); %#ok<ASGLU>
    filename = fullfile(c.sub_results_path,c.sub_features_filename);
    saved = load(filename); saved.resp_cycles = cycles;
    saved.resp_cycles.lungs = rmfield(cycles.lungs,'artifact_intervals_idx');
    saved.resp_cycles.diaph = rmfield(cycles.diaph,'artifact_intervals_idx');
    saved = rmfield(saved,'respiratory_artifact_state'); save(filename,'-struct','saved'); bytes = read_bytes(filename);
    c.resp.recheck_cached = true;
    driver = gui_driver('cancel',cycles); timer_cleanup = onCleanup(@() stop_driver(driver)); %#ok<NASGU>
    [~,cancelled] = load_or_extract_respiratory_cycles(data,c);
    verifyTrue(testCase,cancelled); verifyEmpty(testCase,driver.UserData.error);
    verifyTrue(testCase,driver.UserData.landmarks_seen); verifyEqual(testCase,read_bytes(filename),bytes);
    c.resp.recheck_cached = false; loaded = load_or_extract_respiratory_cycles(data,c);
    verifyEqual(testCase,loaded.lungs.peak_idx,cycles.lungs.peak_idx);
    verifyEqual(testCase,loaded.lungs.trough_overrides,cycles.lungs.trough_overrides);
    verifyEmpty(testCase,loaded.lungs.artifact_intervals_idx);
end

function testReopenAddRemoveCommitAndRevisionMirrors(testCase)
    [c,data,cycles,cleanup] = fixture(); %#ok<ASGLU>
    result_file = fullfile(c.sub_results_path,c.sub_results_filename);
    mask_automatic = logical([0 1;1 0]); review_history = struct('round_id',7,'snapshot',[4 5]); %#ok<NASGU>
    save(result_file,'mask_automatic','review_history');
    h5 = fullfile(c.sub_results_path,'Sub999_M1_results.h5'); h5create(h5,'/sentinel',1); h5write(h5,'/sentinel',42);
    c.resp.recheck_cached = true;
    driver = gui_driver('accept',cycles); timer_cleanup = onCleanup(@() stop_driver(driver)); %#ok<NASGU>
    [loaded,cancelled] = load_or_extract_respiratory_cycles(data,c);
    verifyFalse(testCase,cancelled); verifyEmpty(testCase,driver.UserData.error); verifyTrue(testCase,driver.UserData.landmarks_seen);
    verifyEqual(testCase,loaded.lungs.artifact_intervals_idx,[201 401]);
    verifyEqual(testCase,loaded.diaph.artifact_intervals_idx,[801 1001]);
    verifyEqual(testCase,loaded.lungs.peak_idx,cycles.lungs.peak_idx);
    verifyEqual(testCase,loaded.lungs.trough_idx,cycles.lungs.trough_idx);
    verifyEqual(testCase,loaded.diaph.trough_overrides,cycles.diaph.trough_overrides);
    state = respiratory_artifact_checkpoint('load',c);
    verifyEqual(testCase,state.revision,1); verifyTrue(testCase,state.pending_reanalysis);
    verifyEqual(testCase,state.subject,999); verifyEqual(testCase,state.measurement,1);
    saved = load(result_file); verifyEqual(testCase,saved.mask_automatic,mask_automatic);
    verifyEqual(testCase,saved.review_history,review_history); verifyEqual(testCase,saved.respiratory_artifact_state,state);
    exported = read_artifact_h5(h5);
    verifyEqual(testCase,exported.revision,state.revision); verifyEqual(testCase,h5read(h5,'/sentinel'),42);
    shortened = state; shortened.lungs = zeros(0,2);
    write_respiratory_artifact_hdf5(h5,shortened); shortened = read_artifact_h5(h5);
    verifyEmpty(testCase,shortened.lungs);
    write_respiratory_artifact_hdf5(h5,state); exported = read_artifact_h5(h5);
    verifyEqual(testCase,exported.revision,state.revision);
    other = c; other.measure = 2; other.respiratory_artifact_state = state;
    other.sub_features_filename = 'Sub999_M2_features.mat';
    unseen = respiratory_artifact_checkpoint('load',other);
    verifyEqual(testCase,unseen.measurement,2); verifyEqual(testCase,unseen.revision,0);
    other.sub_features_filename = c.sub_features_filename;
    verifyError(testCase,@() respiratory_artifact_checkpoint('load',other),'MAGMA:Respiration:ArtifactIdentity');
    verifyError(testCase,@() respiratory_artifact_checkpoint('complete',c,0),'MAGMA:Respiration:ArtifactRevisionChanged');
    c.resp.recheck_cached = false; reopened = load_or_extract_respiratory_cycles(data,c);
    verifyEqual(testCase,reopened.lungs,loaded.lungs); verifyEqual(testCase,reopened.diaph,loaded.diaph);
    ref = compute_respiratory_reference(data,reopened,get_session_reference_interval(size(data,1),c),c);
    features = compute_respiratory_features(data,reopened,ref,c);
    verifyEqual(testCase,features.respiratory_artifact_state.revision,1);
end

function testArtifactGuiAlsoWorksWithoutBreathPeaks(testCase)
    [c,data,~,cleanup] = fixture(); %#ok<ASGLU>
    data(:,[4 6]) = 0;
    cycles.lungs = empty_respiration_feature('lungs'); cycles.lungs.x0 = data(:,4);
    cycles.diaph = empty_respiration_feature('diaph'); cycles.diaph.x0 = data(:,6);
    driver = gui_driver('accept',cycles); timer_cleanup = onCleanup(@() stop_driver(driver)); %#ok<NASGU>
    [lungs,diaph,accepted] = manual_edit_respiration_features(data,cycles.lungs,cycles.diaph,c);
    verifyEmpty(testCase,driver.UserData.error); verifyTrue(testCase,accepted);
    verifyEqual(testCase,lungs.artifact_intervals_idx,[201 401]);
    verifyEqual(testCase,diaph.artifact_intervals_idx,[801 1001]);
    verifyEmpty(testCase,lungs.peak_idx); verifyEqual(testCase,lungs.x0,data(:,4));
end

function testFlatAbdomenCanBeMarkedWithThoracicBeltMissing(testCase)
    [c,data,~,cleanup] = fixture(); %#ok<ASGLU>
    c.problems.missing_lung_belt = [c.subject c.measure]; data(:,6) = 0;
    cycles.lungs = empty_respiration_feature('lungs');
    cycles.diaph = empty_respiration_feature('diaph'); cycles.diaph.x0 = data(:,6);
    driver = gui_driver('accept_diaph',cycles); timer_cleanup = onCleanup(@() stop_driver(driver)); %#ok<NASGU>
    [lungs,diaph,accepted] = manual_edit_respiration_features(data,cycles.lungs,cycles.diaph,c);
    verifyEmpty(testCase,driver.UserData.error); verifyTrue(testCase,accepted);
    verifyEmpty(testCase,lungs.artifact_intervals_idx);
    verifyEqual(testCase,diaph.artifact_intervals_idx,[801 1001]);
end

function testFullSyntheticReanalysisUsesCommittedRevision(testCase)
    [c,raw,cycles,cleanup] = fixture(); %#ok<ASGLU>
    root = c.path_results_out; target = fullfile(root,'Sub999_M1'); mkdir(target);
    movefile(fullfile(root,c.sub_features_filename),fullfile(target,c.sub_features_filename));
    input = fullfile(root,'input'); mkdir(input); writematrix(raw,fullfile(input,'synthetic.dat'),'Delimiter',' ');
    c.path_data_in = input; c.input_filename_pattern = 'synthetic.dat'; c.input.filename_pattern = 'synthetic.dat';
    c.subjects = c.subject; c.measurements = c.measure; c.exclude_recordings = [];
    c.overwrite_results = true; c.resp.recheck_cached = true; c.resp.manual_control = true;
    c.HDF5.enabled = true;
    c.LabelMask.do_plot = false; c.PhenotypeSummary.do_plot = false;
    c = rmfield(c,{'sub_results_path','sub_features_filename','sub_results_filename'});
    driver = gui_driver('accept',cycles); timer_cleanup = onCleanup(@() stop_driver(driver)); %#ok<NASGU>
    run_magma(c); verifyEmpty(testCase,driver.UserData.error);
    result = load(fullfile(target,'Sub999_M1_results.mat')); cache = load(fullfile(target,'Sub999_M1_features.mat'));
    verifyEqual(testCase,result.analysis_respiratory_artifact_revision,1);
    verifyFalse(testCase,cache.respiratory_artifact_state.pending_reanalysis);
    verifyFalse(testCase,result.respiratory_artifact_state.pending_reanalysis);
    h5 = fullfile(target,'Sub999_M1_results.h5');
    verifyEqual(testCase,h5read(h5,'/observations/analysis_respiratory_artifact_revision'),1);
    exported = read_artifact_h5(h5);
    verifyFalse(testCase,exported.pending_reanalysis);
    verifyEqual(testCase,h5read(h5,'/breaths/lungs/artifact_intervals_idx'),[201 401]);
    verifyEqual(testCase,result.resp_cycles.lungs.artifact_intervals_idx,[201 401]);
    verifyEqual(testCase,result.resp_cycles.lungs.peak_idx,cycles.lungs.peak_idx);
    verifyEqual(testCase,result.resp_cycles.diaph.trough_overrides,cycles.diaph.trough_overrides);
end

function [c,data,cycles,cleanup] = fixture()
    folder = tempname; mkdir(folder); cleanup = onCleanup(@() remove_fixture(folder));
    c = make_test_config(folder); c.fs = 20; c.verbosity = 0; c.HDF5.enabled = false;
    c.resp.smooth_sec = 0; c.async.analysis_fs = 10;
    c.reference.pre_start_min = 0; c.reference.pre_end_min = 1;
    c.sub_features_filename = 'Sub999_M1_features.mat'; c.sub_results_filename = 'Sub999_M1_results.mat';
    t = (0:4799)'/c.fs; data = zeros(numel(t),6); data(:,3) = 98;
    data(:,4) = sin(2*pi*.25*t); data(:,6) = data(:,4);
    cycles = load_or_extract_respiratory_cycles(data,c);
    for name = {'lungs','diaph'}
        b = cycles.(name{1}); b = set_respiration_trough_override(b,b.peak_idx(2),b.peak_idx(3),b.trough_idx(2)+1,c);
        cycles.(name{1}) = b;
    end
    cycles.provenance.review_status = 'manual_reviewed_edited';
    cycles.provenance.manual_review_performed = true; cycles.provenance.manual_edits_made = true;
    filename = fullfile(folder,c.sub_features_filename); cached = load(filename);
    cached.resp_cycles = cycles; save(filename,'-struct','cached');
end

function driver = gui_driver(action,cycles)
    driver = timer('ExecutionMode','fixedSpacing','Period',.15, ...
        'UserData',struct('error',[],'landmarks_seen',false), ...
        'TimerFcn',@(source,~) drive_gui(source,action,cycles)); start(driver);
end

function drive_gui(driver,action,cycles)
    fig = findall(0,'Tag','respiration_feature_review'); if isempty(fig), return; end
    mode = findall(fig,'Tag','respiration_edit_mode'); done = findall(fig,'Tag','respiration_review_done');
    axl = findall(fig,'Tag','respiration_lungs'); axd = findall(fig,'Tag','respiration_diaph');
    if isempty(mode) || isempty(done) || isempty(axl) || isempty(axd), return; end
    stop(driver); state = driver.UserData;
    try
        red = findall(axl,'MarkerFaceColor',[1 0 0]); blue = findall(axl,'MarkerFaceColor',[0 0 1]);
        if isempty(cycles.lungs.peak_t)
            state.landmarks_seen = isempty(red) && isempty(blue);
        else
            red_t = get(red(1),'XData'); blue_t = get(blue(1),'XData');
            state.landmarks_seen = isequal(red_t(:),cycles.lungs.peak_t(:)) && ...
                isequal(blue_t(:),cycles.lungs.trough_t(:));
        end
        set(mode,'Value',3); callback = get(mode,'Callback'); callback(mode,[]);
        if ~strcmp(action,'accept_diaph')
            drag_artifact(fig,axl,10,20); drag_artifact(fig,axl,70,75);
        end
        drag_artifact(fig,axd,40,50);
        patches = findall(axl,'Tag','respiratory_artifact');
        for k = 1:numel(patches)
            if min(get(patches(k),'XData'))>=69
                callback = get(patches(k),'ButtonDownFcn'); callback(patches(k),[]); break;
            end
        end
        driver.UserData = state;
        if strcmp(action,'cancel'), close(fig); else, callback = get(done,'Callback'); callback(done,[]); end
    catch failure
        state.error = failure; driver.UserData = state; close(fig);
    end
end

function drag_artifact(fig,ax,first,last)
    callback = get(ax,'ButtonDownFcn'); callback(ax,struct('IntersectionPoint',[first 0 0]));
    callback = get(fig,'WindowButtonUpFcn'); callback(fig,struct('IntersectionPoint',[last 0 0]));
end

function stop_driver(driver)
    if isvalid(driver), stop(driver); delete(driver); end
    delete(findall(0,'Tag','respiration_feature_review'));
end

function bytes = read_bytes(filename)
    file = fopen(filename,'rb'); cleanup = onCleanup(@() fclose(file)); %#ok<NASGU>
    bytes = fread(file,Inf,'*uint8');
end

function remove_fixture(folder)
    assert(startsWith(folder,tempdir) && ~strcmp(folder,tempdir)); rmdir(folder,'s');
end

function state = read_artifact_h5(filename)
    encoded = read_hdf5_text(filename,'/observations/respiratory_artifacts_json');
    state = jsondecode(encoded{1});
end
