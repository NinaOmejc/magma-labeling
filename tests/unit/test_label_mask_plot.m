function tests = test_label_mask_plot
% Regression coverage for canonical top-to-bottom label-mask plotting.
    tests = functiontests(localfunctions);
end

function testCanonicalRowsRunFromShallowAtTopToDesatAtBottom(testCase)
    label_names = get_labels('short');
    label_mask = logical(eye(numel(label_names)));
    config = get_config_defaults();
    config.subject = 999;
    config.measure = 1;
    config.make_figs_visible = 'off';
    config.LabelMask.do_plot = true;
    config.LabelMask.use_long_names = false;

    plot_label_mask(label_mask, label_names, config);
    fig = gcf;
    cleanup = onCleanup(@() close_if_valid(fig)); %#ok<NASGU>
    image_handle = findall(fig, 'Type', 'image');
    verifyNumElements(testCase, image_handle, 1);
    ax = ancestor(image_handle, 'axes');
    displayed_labels = cellstr(string(ax.YTickLabel));

    verifyEqual(testCase, ax.YDir, 'reverse');
    verifyEqual(testCase, displayed_labels{1}, 'shallow');
    verifyEqual(testCase, displayed_labels{11}, 'desat');
    verifyEqual(testCase, displayed_labels{end}, 'Respiratory artifact');
    verifySize(testCase,image_handle.CData,[11 11]);
    verifyEqual(testCase, image_handle.CData(1, :), ...
        double(label_mask(:, 1)'));
    verifyEqual(testCase, image_handle.CData(end, :), ...
        double(label_mask(:, end)'));
end

function testNoncanonicalLabelOrderIsRejected(testCase)
    label_names = fliplr(get_labels('short'));
    label_mask = false(2, numel(label_names));
    config = get_config_defaults();
    config.LabelMask.do_plot = true;

    verifyError(testCase, ...
        @() plot_label_mask(label_mask, label_names, config), ...
        'MAGMA:LabelMask:LabelOrder');
end

function testAutomaticArtifactsHaveSeparatePurpleTimelineAndUnassessableCells(testCase)
    labels = get_labels('short'); mask = false(100,11);
    config = get_config_defaults(); config.subject = 999; config.measure = 1;
    config.fs = 10; config.make_figs_visible = 'off';
    config.LabelMask.do_plot = true; config.LabelMask.use_long_names = false;
    config.LabelMask.artifact_context = struct('resp_cycles',struct('artifact_intervals_idx',[31 40]));
    config.LabelMask.assessable_mask = true(size(mask));
    config.LabelMask.assessable_mask(61:65,1) = false; % Unassessable for a non-artifact reason.
    plot_label_mask(mask,labels,config);
    fig = gcf; cleanup = onCleanup(@() close_if_valid(fig)); %#ok<NASGU>
    image = findall(fig,'Type','image');
    verifySize(testCase,image.CData,[11 100]);
    verifyEqual(testCase,image.CData(1:10,31:40),3*ones(10,10));
    verifyEqual(testCase,image.CData(11,31:40),zeros(1,10));
    verifyEqual(testCase,image.CData(1,61:65),3*ones(1,5));
    strips = findall(fig,'Tag','RespiratoryArtifactInterval');
    verifyNumElements(testCase,strips,1); % Assessability gaps did not create artifacts.
    verifyEqual(testCase,strips.FaceColor,[0.53 0.35 0.72]);
    verifyEqual(testCase,strips.Position([1 3]),[3 1]);
    key = findall(fig,'Type','legend');
    verifyTrue(testCase,any(strcmp(key.String,'Respiratory artifact (excluded)')));
    verifyFalse(testCase,any(mask,'all'));
end

function close_if_valid(fig)
% CLOSE_IF_VALID Close the diagnostic figure left open by the no-output test.

    if isgraphics(fig)
        close(fig);
    end
end
