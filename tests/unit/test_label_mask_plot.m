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
    verifyEqual(testCase, displayed_labels{end}, 'desat');
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

function close_if_valid(fig)
% CLOSE_IF_VALID Close the diagnostic figure left open by the no-output test.

    if isgraphics(fig)
        close(fig);
    end
end
