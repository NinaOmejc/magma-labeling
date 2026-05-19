% MAIN_TEST_SIGNALS
% Generate and validate artificial one-label datasets from one source file.

% Add src to path.
src_root = fileparts(mfilename('fullpath'));
repo_root = fileparts(src_root);
if ~isempty(src_root)
    addpath(genpath(src_root));
end

% Create Sub0/Pom1-9 artificial raw files from subject 1, measurement 1.
source_config = get_config();
test_data_dir = fullfile(repo_root, 'test_data');
test_specs = create_artificial_test_data(source_config, test_data_dir, 1, 1, 0, [8 10], true);

% Configure the normal pipeline to read the artificial files.
config = source_config;
config.path_data_in = test_data_dir;
config.path_results_out = fullfile(repo_root, 'results', 'test_signals');
config.subject = 0;
config.overwrite_results = true;
config.overwrite_features = true;
config.make_figs_visible = 'off';
config.save_plots = false;
config.plot_raw_data = false;
config.LabelMask.do_plot = false;
config.LabelMask.save_plot = false;
config.normality.do_plot = false;

config.detrend.do_plot = false;
config.resp.do_plot = false;
config.resp.manual_control = false;
config.rolling_baseline.do_plot = false;
config.ShB.do_plot = false;
config.IrB.do_plot = false;
config.SlB.do_plot = false;
config.RaB.do_plot = false;
config.ReA.do_plot = false;
config.Des.do_plot = false;
config.Apn.do_plot = false;
config.Sig.do_plot = false;
config.Sig.manual_control = false;
config.CSR.do_plot = false;

detected_summary = repmat(struct( ...
    'measure', [], ...
    'expected', '', ...
    'detected', {{}}), numel(test_specs), 1);

for i = 1:numel(test_specs)
    config.measure = test_specs(i).measure;

    [data_raw, config, do_analysis] = load_raw_data(config);
    if ~do_analysis
        continue;
    end

    [data, config] = preprocess_data(data_raw, config);
    resp_feat = load_or_extract_respiratory_features(data, config);

    baseline = compute_baseline(data, config);
    baseline = add_rolling_resp_baseline(baseline, resp_feat, size(data, 1), config);

    spo2_feat = extract_spo2_features(data, baseline, config);

    events_ShB = detect_shallow_breathing(data, baseline, resp_feat, spo2_feat, config);
    events_IrB = detect_irregular_breathing(data, resp_feat, config);
    events_SlB = detect_slow_breathing(data, baseline, resp_feat, spo2_feat, config);
    events_RaB = detect_rapid_breathing(data, baseline, resp_feat, spo2_feat, config);
    [events_ReA, diagnostics_ReA] = detect_respiratory_asynchrony(data, baseline, resp_feat, config);
    events_Des = detect_desaturation(data, baseline, spo2_feat, config);
    events_Apn = detect_apnea(data, baseline, resp_feat, spo2_feat, config);
    events_Sigh = detect_sigh(data, baseline, resp_feat, spo2_feat, config);
    events_CSR = detect_periodic_breathing(data, resp_feat, config);

    sub_events = merge_events({events_ShB, events_IrB, events_SlB, events_RaB, events_ReA, events_Des, events_Apn, events_Sigh, events_CSR});
    sub_events = normalize_event_types_and_meta(sub_events);

    N = size(data, 1);
    [label_mask, label_names] = events_to_time_mask(sub_events, N, config);
    plot_label_mask(label_mask, label_names, config);
    diagnostic_signals = compute_label_diagnostic_signals(data, baseline, resp_feat, spo2_feat, config, diagnostics_ReA);

    results.subject = config.subject;
    results.measure = config.measure;
    results.events = sub_events;
    results.mask = label_mask;
    results.label_names = label_names;
    results.resp_feat = resp_feat;
    results.spo2_feat = spo2_feat;
    results.diagnostic_signals = diagnostic_signals;
    results.baseline = baseline;
    results.config = config;
    save(fullfile(config.sub_results_path, config.sub_results_filename), '-struct', 'results');

    expected_label = test_specs(i).label_short;
    detected_labels = detected_event_types(sub_events);
    extra_labels = assert_expected_present(config.measure, expected_label, detected_labels);

    detected_summary(i).measure = config.measure;
    detected_summary(i).expected = expected_label;
    detected_summary(i).detected = detected_labels;

    if isempty(extra_labels)
        fprintf('Sub0 M%d passed: expected %s, detected %s\n', ...
            config.measure, expected_label, strjoin(detected_labels, ', '));
    else
        fprintf('Sub0 M%d passed: expected %s was found; additional labels detected: %s\n', ...
            config.measure, expected_label, strjoin(extra_labels, ', '));
    end
end

save(fullfile(config.path_results_out, 'test_signal_validation_summary.mat'), ...
    'detected_summary', 'test_specs');

disp('All artificial test signals contain their expected labels.');

function labels = detected_event_types(events)
    if isempty(events)
        labels = {};
        return;
    end

    labels = unique({events.type});
    labels = labels(~cellfun('isempty', labels));
end

function unexpected = assert_expected_present(measure, expected_label, detected_labels)
    if ~ismember(expected_label, detected_labels)
        error('Sub0 M%d expected %s, but detected: %s', ...
            measure, expected_label, strjoin_or_none(detected_labels));
    end

    unexpected = setdiff(detected_labels, {expected_label});
end

function text_out = strjoin_or_none(values)
    if isempty(values)
        text_out = '<none>';
    else
        text_out = strjoin(values, ', ');
    end
end
