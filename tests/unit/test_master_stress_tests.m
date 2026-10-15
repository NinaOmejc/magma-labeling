function tests = test_master_stress_tests
% Small integration fixtures for source-test rows and future workbook growth.
    tests = functiontests(localfunctions);
end

function test_source_rows_repeat_identity_and_missing_values(testCase)
    [config,cleanup] = fixture(); %#ok<ASGLU>
    database = build_master_database(config);
    T = database.tables.StressTest;
    verifyEqual(testCase,height(T),3);
    verifyEqual(testCase,T.participant_id,repmat("Sub87",3,1));
    verifyEqual(testCase,T.visit_number,[1;1;2]);
    verifyEqual(testCase,T.test_no,["st 1";"st 2";"st 1"]);
    verifyEqual(testCase,T.peak_workload_w{1},0);
    verifyEqual(testCase,string(T.peak_workload_w{2}),"not recorded");
    verifyFalse(testCase,any(ismember({'measure','recording_id','longitudinal_measure'},T.Properties.VariableNames)));
    verifyEqual(testCase,numel(unique(T.stress_test_record_id)),height(T));
    verifyTrue(testCase,all(isnat(T.import_study_date)));
    verifyFalse(testCase,any(database.audit.severity=="error"));
    verifyTrue(testCase,any(endsWith(database.output_files.csv,'StressTest.csv')));
end

function test_refresh_adds_subject_tests_and_columns_without_stale_rows(testCase)
    [config,cleanup] = fixture(); %#ok<ASGLU>
    build_master_database(config);
    stress = config.sources(end);
    writecell({'Sub_code','Test no.','Test date','Peak workload (W)','Clinical note','New value'; ...
        'Sub87','st 1','2025-01-01',0,'original',42; ...
        'Sub999','st 3','2026-10-13',120,'new subject',7; ...
        'Sub999','st 3','2026-10-13',120,'new subject',7},stress.file,'Sheet',stress.sheet,'WriteMode','overwritesheet');
    database = build_master_database(config);
    T = database.tables.StressTest;
    verifyEqual(testCase,height(T),3);
    verifyEqual(testCase,T.participant_number,[87;999;999]);
    verifyEqual(testCase,T.new_value,[42;7;7]);
    verifyTrue(testCase,ismember("Sub999",database.tables.Subjects.participant_id));
    verifyEqual(testCase,sum(database.audit.issue=="duplicate_stress_test_source_record"),1);
    exported = readtable(database.output_files.workbook,'Sheet','StressTest','TextType','string');
    verifyEqual(testCase,height(exported),3);
    verifyFalse(testCase,any(exported.source_subject_id=="Sub117"));
    verifyTrue(testCase,ismember("new_value",database.import_mapping.output_column));
end

function test_empty_stress_source_and_original_three_argument_config(testCase)
    [config,cleanup] = fixture(); %#ok<ASGLU>
    stress = config.sources(end);
    writecell({'Sub_code','Test no.','Test date','Peak workload (W)','Clinical note'}, ...
        stress.file,'Sheet',stress.sheet,'WriteMode','overwritesheet');
    database = build_master_database(config);
    verifyEqual(testCase,height(database.tables.StressTest),0);
    old = get_master_database_config(config.sources(4).file,config.sources(1).file,config.output_dir);
    old.references = config.references; old.export_mat = false; old.format_workbook = false;
    database = build_master_database(old);
    verifyFalse(testCase,isfield(database.tables,'StressTest'));
    verifyFalse(testCase,ismember("StressTest",string(sheetnames(database.output_files.workbook))));
end

function [config,cleanup] = fixture()
    folder = tempname; mkdir(folder);
    cleanup = onCleanup(@() rmdir(folder,'s'));
    collaborator = fullfile(folder,'collaborator.xlsx');
    group = fullfile(folder,'group.xlsx'); stress = fullfile(folder,'stress.xlsx');
    for m=1:2
        writecell({'Physiology','';'Subject','Value';'Sub87',1;'Sub117',2}, ...
            collaborator,'Sheet',sprintf('Measurement_%d',m));
    end
    writecell({'Questionnaire','','','','';'Sub_code','grp','dob','sex','dt_study'; ...
        'Sub87',1,'1980-01-01','F','2025-01-01'},collaborator,'Sheet','Questionnaire');
    writecell({'first measurement ID','repeated measurement ID';'Sub87','Sub117'}, ...
        collaborator,'Sheet','Repeat measurements_mapping ID');
    writecell({'subject','recording_id','measure','subject_group','label','fraction'; ...
        87,'Sub87_M1',1,'Patient','slow',0;117,'Sub117_M1',1,'Unknown','slow',0.1},group,'Sheet','Label_burden');
    writecell({'subject','recording_id','measure','subject_group','annotation_layer','value'; ...
        87,'Sub87_M1',1,'Patient','automatic',1;117,'Sub117_M1',1,'Unknown','reviewed',NaN},group,'Sheet','Phenotypes');
    writecell({'Sub_code','Test no.','Test date','Peak workload (W)','Clinical note'; ...
        'Sub87','st 1','2025-01-01',0,sprintf('Polish note\nsecond line'); ...
        'Sub87','st 2','not recorded','not recorded','unknown'; ...
        'Sub117','st 1','2020-01-01',100,'repeat'},stress,'Sheet','Stress_tests');
    config = get_master_database_config(group,collaborator,fullfile(folder,'out'),stress);
    config.references = struct('name',{},'file',{},'sheet',{});
    config.export_mat = false; config.format_workbook = false;
end


