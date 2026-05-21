function test_specs = create_artificial_test_data(config, output_dir, source_subject, source_measure, test_subject, trange_min, force_overwrite)
%CREATE_ARTIFICIAL_TEST_DATA Create one-label artificial raw datasets.
%
% The generated files keep the standard raw-data filename convention, so
% load_raw_data can process them without a special test loader:
%
%   ECG1_ECG2_SpO2_RespL_BP_RespD_fs200_Sub0_Pom1_DeTr_Norm.dat
%   ...
%   ECG1_ECG2_SpO2_RespL_BP_RespD_fs200_Sub0_Pom9_DeTr_Norm.dat
%
% Measurements 1-9 map to labels shallowB, irregB, slowB, rapidB, asyncB, desat, apnea, sigh, CSR.

    if nargin < 2 || isempty(output_dir)
        repo_root = fileparts(fileparts(mfilename('fullpath')));
        output_dir = fullfile(repo_root, 'test_data');
    end
    if nargin < 3 || isempty(source_subject)
        source_subject = 1;
    end
    if nargin < 4 || isempty(source_measure)
        source_measure = 1;
    end
    if nargin < 5 || isempty(test_subject)
        test_subject = 0;
    end
    if nargin < 6 || isempty(trange_min)
        trange_min = [8 10];
    end
    if nargin < 7 || isempty(force_overwrite)
        force_overwrite = true;
    end

    if ~isfolder(output_dir)
        mkdir(output_dir);
    end

    source_file = raw_filename(config.path_data_in, source_subject, source_measure);
    if ~exist(source_file, 'file')
        error('Source raw data file not found: %s', source_file);
    end

    source_data = load(source_file);
    n_columns = numel(config.data_columns);
    source_data = reshape(source_data, [], n_columns);
    template_data = clean_template_from_source(source_data, config);

    idx_spo2 = find_column(config, 'SpO');
    idx_lungs = find_column(config, 'Resp-Lungs');
    idx_diaph = find_column(config, 'Resp-Diaphragm');

    test_specs = build_test_specs(idx_spo2, idx_lungs, idx_diaph);

    for i = 1:numel(test_specs)
        measure = test_specs(i).measure;
        out_file = raw_filename(output_dir, test_subject, measure);
        test_specs(i).file = out_file;

        if exist(out_file, 'file') && ~force_overwrite
            fprintf('Keeping existing artificial test data: %s\n', out_file);
            continue;
        end

        this_trange_min = test_trange_for_spec(test_specs(i), trange_min, size(template_data, 1), config.fs);

        data_modified = modify_data_to_test( ...
            template_data, config.fs, test_specs(i).columns, this_trange_min, ...
            test_specs(i).modification_type, false);

        save(out_file, 'data_modified', '-ascii', '-double');
        fprintf('Wrote artificial test data: %s -> %s\n', out_file, test_specs(i).label_short);
    end

    write_expected_labels(output_dir, test_specs, test_subject, trange_min, size(template_data, 1), config.fs);
end

function data_out = clean_template_from_source(source_data, config)
% Keep source ECG/BP columns and replace channels that drive the detectors
% with clean baseline signals. This prevents accidental labels from the
% real source recording while preserving the original recording length.
    data_out = source_data;
    fs = config.fs;
    N = size(source_data, 1);
    t = (0:N-1)' / fs;

    idx_spo2 = find_column(config, 'SpO');
    idx_lungs = find_column(config, 'Resp-Lungs');
    idx_diaph = find_column(config, 'Resp-Diaphragm');

    if ~isempty(idx_spo2)
        data_out(:, idx_spo2) = 97 + 0.05 * sin(2 * pi * 0.01 * t);
    end

    baseline_bpm = 12;
    baseline_phase = 2 * pi * (baseline_bpm / 60) * t;
    if ~isempty(idx_lungs)
        data_out(:, idx_lungs) = sin(baseline_phase);
    end
    if ~isempty(idx_diaph)
        data_out(:, idx_diaph) = 0.85 * sin(baseline_phase + 0.06);
    end
end

function test_specs = build_test_specs(idx_spo2, idx_lungs, idx_diaph)
    resp_columns = [idx_lungs idx_diaph];
    resp_columns = resp_columns(isfinite(resp_columns) & resp_columns > 0);

    template = struct( ...
        'measure', [], ...
        'label_short', '', ...
        'label_long', '', ...
        'modification_type', '', ...
        'columns', [], ...
        'file', '');
    test_specs = repmat(template, 9, 1);

    test_specs(1) = make_spec(1, 'shallowB', 'ShallowBreathing', 'shallow_breathing', resp_columns);
    test_specs(2) = make_spec(2, 'irregB', 'IrregularBreathing', 'irregular_breathing', resp_columns);
    test_specs(3) = make_spec(3, 'slowB', 'SlowBreathing', 'slow_breathing', resp_columns);
    test_specs(4) = make_spec(4, 'rapidB', 'RapidBreathing', 'rapid_breathing', resp_columns);
    test_specs(5) = make_spec(5, 'asyncB', 'RespiratoryAsynchrony', 'respiratory_asynchrony', resp_columns);
    test_specs(6) = make_spec(6, 'desat', 'Desaturation', 'desaturation', idx_spo2);
    test_specs(7) = make_spec(7, 'apnea', 'Apnea', 'apnea', resp_columns);
    test_specs(8) = make_spec(8, 'sigh', 'Sigh', 'sigh', resp_columns);
    test_specs(9) = make_spec(9, 'CSR', 'PeriodicBreathingCheyneStokesLike', 'periodic_breathing', resp_columns);
end

function spec = make_spec(measure, label_short, label_long, modification_type, columns)
    spec = struct( ...
        'measure', measure, ...
        'label_short', label_short, ...
        'label_long', label_long, ...
        'modification_type', modification_type, ...
        'columns', columns, ...
        'file', '');
end

function trange_out = test_trange_for_spec(~, default_trange_min, ~, ~)
    trange_out = default_trange_min;
end

function write_expected_labels(output_dir, test_specs, test_subject, trange_min, n_samples, fs)
    measure = [test_specs.measure]';
    label_short = {test_specs.label_short}';
    label_long = {test_specs.label_long}';
    modification_type = {test_specs.modification_type}';
    subject = repmat(test_subject, numel(test_specs), 1);
    event_start_min = nan(numel(test_specs), 1);
    event_end_min = nan(numel(test_specs), 1);
    for i = 1:numel(test_specs)
        this_trange_min = test_trange_for_spec(test_specs(i), trange_min, n_samples, fs);
        event_start_min(i) = this_trange_min(1);
        event_end_min(i) = this_trange_min(2);
    end

    expected_labels = table(subject, measure, label_short, label_long, ...
        modification_type, event_start_min, event_end_min);
    out_file = fullfile(output_dir, 'expected_labels.csv');
    writetable(expected_labels, out_file);
end

function idx = find_column(config, pattern)
    idx = find(contains(config.data_columns, pattern), 1);
    if isempty(idx)
        idx = NaN;
    end
end

function filename = raw_filename(folder, subject, measure)
    filename = fullfile(folder, sprintf( ...
        'ECG1_ECG2_SpO2_RespL_BP_RespD_fs200_Sub%d_Pom%d_DeTr_Norm.dat', ...
        subject, measure));
end
