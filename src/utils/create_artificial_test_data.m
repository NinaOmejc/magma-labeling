function test_specs = create_artificial_test_data(config, output_dir, source_subject, source_measure, test_subject, trange_min, force_overwrite)
% CREATE_ARTIFICIAL_TEST_DATA Create artificial test data.
%
% Syntax:
%   test_specs = create_artificial_test_data(config, output_dir, source_subject, source_measure, test_subject, trange_min, force_overwrite)
%
% Inputs:
%   config - Pipeline configuration structure.
%   output_dir - File or dataset path.
%   source_subject - Subject identifier.
%   source_measure - Measurement identifier.
%   test_subject - Subject identifier.
%   trange_min - Input value `trange_min`.
%   force_overwrite - Input value `force_overwrite`.
%
% Outputs:
%   test_specs - Computed output value `test_specs`.

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
% CLEAN_TEMPLATE_FROM_SOURCE Perform the clean template from source operation.
%
% Syntax:
%   data_out = clean_template_from_source(source_data, config)
%
% Inputs:
%   source_data - Input physiological signal data.
%   config - Pipeline configuration structure.
%
% Outputs:
%   data_out - Computed output value `data_out`.

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

    nominal_bpm = 12;
    nominal_phase = 2 * pi * (nominal_bpm / 60) * t;
    if ~isempty(idx_lungs)
        data_out(:, idx_lungs) = sin(nominal_phase);
    end
    if ~isempty(idx_diaph)
        data_out(:, idx_diaph) = 0.85 * sin(nominal_phase + 0.06);
    end
end

function test_specs = build_test_specs(idx_spo2, idx_lungs, idx_diaph)
% BUILD_TEST_SPECS Build test specs.
%
% Syntax:
%   test_specs = build_test_specs(idx_spo2, idx_lungs, idx_diaph)
%
% Inputs:
%   idx_spo2 - Input value `idx_spo2`.
%   idx_lungs - Input value `idx_lungs`.
%   idx_diaph - Input value `idx_diaph`.
%
% Outputs:
%   test_specs - Computed output value `test_specs`.

    resp_columns = [idx_lungs idx_diaph];
    resp_columns = resp_columns(isfinite(resp_columns) & resp_columns > 0);

    template = struct( ...
        'measure', [], ...
        'label_short', '', ...
        'label_long', '', ...
        'modification_type', '', ...
        'columns', [], ...
        'file', '');
    test_specs = repmat(template, 11, 1);

    test_specs(1) = make_spec(1, 'shallow', 'ShallowBreathing', 'shallow_breathing', resp_columns);
    test_specs(2) = make_spec(2, 'deep', 'DeepBreathing', 'deep_breathing', resp_columns);
    test_specs(3) = make_spec(3, 'slow', 'SlowBreathing', 'slow_breathing', resp_columns);
    test_specs(4) = make_spec(4, 'rapid', 'RapidBreathing', 'rapid_breathing', resp_columns);
    test_specs(5) = make_spec(5, 'irregular', 'IrregularBreathing', 'irregular_breathing', resp_columns);
    test_specs(6) = make_spec(6, 'apnea', 'Apnea', 'apnea', resp_columns);
    test_specs(7) = make_spec(7, 'sigh', 'Sigh', 'sigh', resp_columns);
    test_specs(8) = make_spec(8, 'csr', 'PeriodicBreathingCheyneStokesLike', 'periodic_breathing', resp_columns);
    test_specs(9) = make_spec(9, 'thoracic', 'ThoracicDominantBreathing', 'thoracic_dominant_breathing', resp_columns);
    test_specs(10) = make_spec(10, 'async', 'RespiratoryAsynchrony', 'respiratory_asynchrony', resp_columns);
    test_specs(11) = make_spec(11, 'desat', 'Desaturation', 'desaturation', idx_spo2);
end

function spec = make_spec(measure, label_short, label_long, modification_type, columns)
% MAKE_SPEC Create spec.
%
% Syntax:
%   spec = make_spec(measure, label_short, label_long, modification_type, columns)
%
% Inputs:
%   measure - Measurement identifier.
%   label_short - Label identifier or label metadata.
%   label_long - Label identifier or label metadata.
%   modification_type - Input value `modification_type`.
%   columns - Input value `columns`.
%
% Outputs:
%   spec - Computed output value `spec`.

    spec = struct( ...
        'measure', measure, ...
        'label_short', label_short, ...
        'label_long', label_long, ...
        'modification_type', modification_type, ...
        'columns', columns, ...
        'file', '');
end

function trange_out = test_trange_for_spec(~, default_trange_min, ~, ~)
% TEST_TRANGE_FOR_SPEC Perform the test trange for spec operation.
%
% Syntax:
%   trange_out = test_trange_for_spec(~, default_trange_min, ~, ~)
%
% Inputs:
%   ~ - Unused positional input.
%   default_trange_min - Input value `default_trange_min`.
%   ~ - Unused positional input.
%   ~ - Unused positional input.
%
% Outputs:
%   trange_out - Computed output value `trange_out`.

    trange_out = default_trange_min;
end

function write_expected_labels(output_dir, test_specs, test_subject, trange_min, n_samples, fs)
% WRITE_EXPECTED_LABELS Write expected labels.
%
% Syntax:
%   write_expected_labels(output_dir, test_specs, test_subject, trange_min, n_samples, fs)
%
% Inputs:
%   output_dir - File or dataset path.
%   test_specs - Input value `test_specs`.
%   test_subject - Subject identifier.
%   trange_min - Input value `trange_min`.
%   n_samples - Number of samples.
%   fs - Sampling frequency in hertz.

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
% FIND_COLUMN Find column.
%
% Syntax:
%   idx = find_column(config, pattern)
%
% Inputs:
%   config - Pipeline configuration structure.
%   pattern - Input value `pattern`.
%
% Outputs:
%   idx - Computed index or count value.

    idx = find(contains(config.data_columns, pattern), 1);
    if isempty(idx)
        idx = NaN;
    end
end

function filename = raw_filename(folder, subject, measure)
% RAW_FILENAME Perform the raw filename operation.
%
% Syntax:
%   filename = raw_filename(folder, subject, measure)
%
% Inputs:
%   folder - Input value `folder`.
%   subject - Subject identifier.
%   measure - Measurement identifier.
%
% Outputs:
%   filename - Output text or identifier.

    filename = fullfile(folder, sprintf( ...
        'ECG1_ECG2_SpO2_RespL_BP_RespD_fs200_Sub%d_Pom%d_DeTr_Norm.dat', ...
        subject, measure));
end
