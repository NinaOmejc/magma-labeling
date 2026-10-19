function tests = test_hierarchical_results_workflows
% One small synthetic recording; no cohort or real recording files.
    tests = functiontests(localfunctions);
end

function testRegenerationReviewCancellationAndSelectedRerun(testCase)
    root = tempname; mkdir(root); cleanup = onCleanup(@() rmdir(root,'s')); %#ok<NASGU>
    config = make_test_config(root); config.fs = 20; config.verbosity = 0;
    config.subjects = 999; config.measurements = 1; config.exclude_recordings = [];
    config.resp.recheck_cached = false; config.resp.smooth_sec = 0;
    config.overwrite_results = true; config.overwrite_features = false;
    config.HDF5.enabled = false; config.LabelMask.do_plot = false; config.PhenotypeSummary.do_plot = false;
    folder = fullfile(root,'Sub999_M1'); mkdir(folder);
    config.sub_results_path = folder; config.sub_features_filename = 'Sub999_M1_features.mat';
    config.sub_results_filename = 'Sub999_M1_results.mat';
    raw = make_synthetic_master_data(2001,config.fs);
    [data,seed_config] = preprocess_data(raw,config);
    cycles = load_or_extract_respiratory_cycles(data,seed_config);
    for name = {'lungs','diaph'}
        b = cycles.(name{1});
        cycles.(name{1}) = set_respiration_trough_override(b,b.peak_idx(2),b.peak_idx(3),b.trough_idx(2)+1,seed_config);
    end
    cycles.provenance.manual_review_performed = true;
    cycles.provenance.manual_edits_made = true;
    cycles.provenance.review_status = 'manual_reviewed_edited';
    cycles = rmfield(cycles,'artifact_intervals_idx');
    cycles.lungs.artifact_intervals_idx = [301 320]; cycles.diaph.artifact_intervals_idx = [320 330];
    cache_file = fullfile(folder,config.sub_features_filename);
    cached = load(cache_file); cached.resp_cycles = cycles; atomic_save_mat(cache_file,cached);
    input = fullfile(root,'input'); mkdir(input);
    writematrix(raw,fullfile(input,'synthetic.dat'),'Delimiter',' ');
    config.path_data_in = input; config.input_filename_pattern = 'synthetic.dat';
    config.input.filename_pattern = 'synthetic.dat';
    result_file = fullfile(folder,config.sub_results_filename);
    obsolete_marker = true; save(result_file,'obsolete_marker');
    config = rmfield(config,{'sub_results_path','sub_features_filename','sub_results_filename'});
    old_warning = warning('off','MAGMA:Results:Regenerate');
    cleanup_warning = onCleanup(@() warning(old_warning)); %#ok<NASGU>
    run_magma(config);
    verifyEqual(testCase,who('-file',result_file),{'results'});
    automatic = recording_results('load',result_file);
    verifySize(testCase,automatic.mask_automatic,[2001 11]);
    verifyEqual(testCase,automatic.phenotypes.automatic.numeric_summary.n_features,24);
    verifyEqual(testCase,automatic.resp_cycles.artifact_intervals_idx,[301 330]);
    preserved = {'peak_idx','trough_idx','trough_overrides','amp','amp_exp','amp_insp','amp_sym','x0'};
    for name = {'lungs','diaph'}
        for k=1:numel(preserved)
            verifyTrue(testCase,isequaln(automatic.resp_cycles.(name{1}).(preserved{k}),cycles.(name{1}).(preserved{k})),preserved{k});
        end
    end
    config.execution.mode = 'analyze_and_review';
    driver = label_driver(false); cleanup_driver = onCleanup(@() stop_driver(driver));
    run_magma(config); verifyTrue(testCase,driver.UserData.acted); clear cleanup_driver;
    first = recording_results('load',result_file);
    verifyNumElements(testCase,first.review_history,1);
    verifyEqual(testCase,first.mask_automatic,automatic.mask_automatic);
    config.execution.mode = 'review_only'; config.LabelEdit.start_from = 'latest_reviewed';
    driver = label_driver(false); cleanup_driver = onCleanup(@() stop_driver(driver));
    run_magma(config); verifyTrue(testCase,driver.UserData.acted); clear cleanup_driver;
    second = recording_results('load',result_file);
    verifyNumElements(testCase,second.review_history,2);
    verifyEqual(testCase,second.review_history(1),first.review_history(1));
    verifyEqual(testCase,second.mask_automatic,first.mask_automatic);
    verifyEqual(testCase,second.label_evidence_summary_automatic,first.label_evidence_summary_automatic);
    verifyEqual(testCase,second.phenotypes.automatic,first.phenotypes.automatic);
    before = read_bytes(result_file); cache_before = read_bytes(cache_file);
    driver = label_driver(true); cleanup_driver = onCleanup(@() stop_driver(driver));
    run_magma(config); verifyTrue(testCase,driver.UserData.acted); clear cleanup_driver;
    verifyEqual(testCase,read_bytes(result_file),before);
    verifyEqual(testCase,read_bytes(cache_file),cache_before);
    config.execution.mode = 'analyze'; config.execution.selected_labels = {'rapid'};
    run_magma(config); selected = recording_results('load',result_file);
    unchanged = ~strcmp(selected.label_names,'rapid');
    verifyEqual(testCase,selected.mask_automatic(:,unchanged),second.mask_automatic(:,unchanged));
    verifyEqual(testCase,selected.review_history,second.review_history);
    verifyEqual(testCase,who('-file',result_file),{'results'});
end

function driver = label_driver(cancel)
    driver = timer('ExecutionMode','fixedSpacing','Period',0.1, ...
        'UserData',struct('acted',false,'ticks',0),'TimerFcn',@(source,~) finish_label_gui(source,cancel));
    start(driver);
end

function finish_label_gui(driver,cancel)
    state = driver.UserData; state.ticks = state.ticks+1; driver.UserData = state;
    figure = findall(0,'Type','figure','Name','Manual label event editor');
    if isempty(figure), return; end
    button = findall(figure(1),'Style','pushbutton','String','Done');
    if isempty(button), return; end
    stop(driver); state.acted = true; driver.UserData = state;
    if cancel, close(figure(1)); else, callback = button(1).Callback; callback(button(1),[]); end
end

function stop_driver(driver)
    if isvalid(driver), stop(driver); delete(driver); end
    figures = findall(0,'Type','figure','Name','Manual label event editor');
    delete(figures);
end

function bytes = read_bytes(filename)
    fid = fopen(filename,'rb'); cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
    bytes = fread(fid,Inf,'*uint8');
end
