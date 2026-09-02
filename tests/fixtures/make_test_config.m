function config = make_test_config(output_dir)
% make_test_config  Non-interactive 200 Hz configuration for automated tests.

    if nargin < 1 || isempty(output_dir)
        output_dir = tempname;
    end

    config = get_config();
    config.subject = 999;
    config.measure = 1;
    config.path_results_out = output_dir;
    config.sub_results_path = output_dir;
    config.sub_features_filename = 'test_features.mat';
    config.overwrite_features = false;
    config.make_figs_visible = 'off';
    config.plot_raw_data = false;
    config.problems.subjects_with_broken_lung_belt = [];

    config.detrend.do_plot = false;
    config.resp.do_plot = false;
    config.resp.manual_control = false;
    config.resp.qc.enabled = false;
    config.resp_ref.do_plot = false;
    config.normality.do_plot = false;
    config.rolling_baseline.do_plot = false;
    config.Sig.do_plot = false;
    config.Sig.manual_control = false;
    config.LabelEdit.manual_control = false;
    config.LabelEdit.apply_saved_edits = false;
    config.LabelEdit.save_edits = false;

    detector_fields = {'ShB', 'IrB', 'SlB', 'RaB', 'ReA', 'Des', 'Apn', 'CSR'};
    for i = 1:numel(detector_fields)
        config.(detector_fields{i}).do_plot = false;
    end

    config = resolve_signal_channels(config);
end
