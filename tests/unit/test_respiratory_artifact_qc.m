function tests = test_respiratory_artifact_qc
% Small metadata/grid checks; no extraction or recording analysis.
    tests = functiontests(localfunctions);
end

function testCoverageCountsUnionOnce(testCase)
    recording = struct('resp_cycles',struct('artifact_intervals_idx', ...
        [3 5;5 8;9 9;20 20]));
    [qc,state] = respiratory_artifact_qc(recording,100,10);
    verifyEqual(testCase,state.artifact_intervals_idx,[3 9;20 20]);
    verifyEqual(testCase,qc.respiratory_artifact_duration_sec,0.8,'AbsTol',eps);
    verifyEqual(testCase,qc.respiratory_artifact_fraction,0.08,'AbsTol',eps);
    verifyEqual(testCase,qc.respiratory_artifact_n_intervals,2);
end

function testKnownEmptyDiffersFromMissingLegacyMetadata(testCase)
    empty = struct('resp_cycles',struct('artifact_intervals_idx',zeros(0,2)));
    known = respiratory_artifact_qc(empty,100,10);
    missing = respiratory_artifact_qc(struct(),100,10);
    verifyTrue(testCase,known.respiratory_artifact_annotation_known);
    verifyEqual(testCase,known.respiratory_artifact_duration_sec,0);
    verifyFalse(testCase,missing.respiratory_artifact_annotation_known);
    verifyTrue(testCase,isnan(missing.respiratory_artifact_duration_sec));
    verifyTrue(testCase,isnan(missing.respiratory_artifact_fraction));
    verifyFalse(testCase,missing.automatic_respiratory_training_eligible);
end

function testLegacyUnionAndStaleRevisionDetection(testCase)
    legacy = struct('resp_cycles',struct('lungs',struct('artifact_intervals_idx',[2 4]), ...
        'diaph',struct('artifact_intervals_idx',[4 6])));
    qc = respiratory_artifact_qc(legacy,100,10);
    verifyEqual(testCase,qc.respiratory_artifact_duration_sec,0.5);
    verifyTrue(testCase,qc.respiratory_artifact_pending_reanalysis);
    state = respiratory_artifact_state(struct('artifact_intervals_idx',[2 6]),struct('fs',10),100);
    state.revision = 4;
    recording = struct('respiratory_artifact_state',state,'analysis_respiratory_artifact_revision',3);
    qc = respiratory_artifact_qc(recording,100,10);
    verifyFalse(testCase,qc.automatic_respiratory_results_current);
    recording.analysis_respiratory_artifact_revision = 4;
    qc = respiratory_artifact_qc(recording,100,10);
    verifyTrue(testCase,qc.automatic_respiratory_results_current);
end

function testMlGridExcludesFilterSupportAndKeepsDesaturationIndependent(testCase)
    time = (0:0.1:5)';
    state = struct('artifact_intervals_idx',[201 201],'annotation_known',true);
    valid = respiratory_artifact_ml_validity(state,1001,200,time,1);
    verifyFalse(testCase,any(valid(time<=2)));
    verifyTrue(testCase,all(valid(time>2)));
    labels = get_labels('short');
    training = ml_label_assessability(true(1001,11),labels,time,200,10,valid,false);
    verifyFalse(testCase,any(training(:,1:10),'all'));
    verifyTrue(testCase,all(training(:,11)));
    verifySize(testCase,training,[numel(time) 11]);
end
