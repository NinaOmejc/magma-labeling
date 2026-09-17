function [data, config, do_analysis] = load_raw_data(config)
% LOAD_RAW_DATA Load one recording and determine whether it should be analysed.
% config identifies channels, subject/measurement, input/results paths, naming,
% overwrite policy, and fs. data is Nsample-by-Nconfigured-channel. Returned
% config adds resolved channels/input_config, per-recording result/cache paths,
% filenames, and native sample times in seconds. do_analysis is false and data
% empty when an existing result should be kept; configured broken lung belts
% are zeroed before analysis.

    [config, input_config] = resolve_signal_channels(config);

    % PREPARE OUTPUT FOLDER
    config.sub_results_path = [config.path_results_out filesep 'Sub' num2str(config.subject) '_M' num2str(config.measure)];
    config.sub_results_filename = ['Sub' num2str(config.subject) '_M' num2str(config.measure) '_labels.mat'];
    config.sub_features_filename = ['Sub' num2str(config.subject) '_M' num2str(config.measure) '_features.mat'];

    do_analysis = true;
    if isfolder(config.sub_results_path) && exist([config.sub_results_path filesep config.sub_results_filename] , 'file')
        if config.overwrite_results
            do_analysis = true;
            log_message(config, 1, ...
                'Overwritting analysis for: Sub %d | Measurement: %d', ...
                config.subject, config.measure);
        else
            do_analysis = false;
            data = [];
            log_message(config, 1, ...
                'Skipping analysis, as results already exist: Sub %d | Measurement: %d', ...
                config.subject, config.measure);
            return
        end
    else
        if ~isfolder(config.sub_results_path)
            mkdir(config.sub_results_path);
        end
        log_message(config, 1, ...
            'Successfully loaded data: Sub %d | Measurement: %d', ...
            config.subject, config.measure);
    end

    % LOAD DATA
    filename = resolve_input_filename(config);
    
    full_fname = [config.path_data_in filesep filename];
    if exist(full_fname, 'file')
        data = load(full_fname);
    elseif exist(strrep(full_fname, '.dat', '_Glue.dat'), 'file')
        data = load(strrep(full_fname, '.dat', '_Glue.dat'));
    else
        error(['File could not be loaded: ' full_fname])
    end

    data = reshape_loaded_data(data, numel(config.data_columns), full_fname);
    print_input_configuration(input_config, config);

    % CHECK PROBLEMS
    if is_lung_belt_ignored(config)
        lung_idx = config.channels.lungs_idx;
        if ~isempty(lung_idx)
            data(:, lung_idx) = data(:, lung_idx) * 0;
        end
    end

    % Master sample times stay on the native config.fs timeline.
    config.times = (0:size(data,1)-1)' / config.fs;

    % PLOT RAW DATA
    plot_raw_data(data, config);
    
end

function filename = resolve_input_filename(config)
% RESOLVE_INPUT_FILENAME Expand subject/measurement tokens in the input pattern.

    pattern = 'ECG1_ECG2_SpO2_RespL_BP_RespD_fs200_Sub{subject}_Pom{measure}_DeTr_Norm.dat';
    if isfield(config, 'input') && isfield(config.input, 'filename_pattern') && ...
            ~isempty(config.input.filename_pattern)
        pattern = config.input.filename_pattern;
    elseif isfield(config, 'input_filename_pattern') && ~isempty(config.input_filename_pattern)
        pattern = config.input_filename_pattern;
    end

    filename = char(string(pattern));
    filename = strrep(filename, '{subject}', num2str(config.subject));
    filename = strrep(filename, '{measure}', num2str(config.measure));
end

function data = reshape_loaded_data(raw_data, n_cols, filename)
% RESHAPE_LOADED_DATA Enforce the configured channel width after loading.
% Matrices already N-by-n_cols pass through; vectors are reshaped when their
% length is divisible by n_cols. filename identifies malformed input in errors.

    if isempty(raw_data)
        error('Loaded data is empty: %s', filename);
    end

    if size(raw_data, 2) == n_cols
        data = raw_data;
        return;
    end

    if ~isvector(raw_data)
        error(['Loaded data column mismatch for %s. config.data_columns has %d entries, ' ...
            'but the loaded array is %d x %d.'], ...
            filename, n_cols, size(raw_data, 1), size(raw_data, 2));
    end

    if mod(numel(raw_data), n_cols) == 0
        data = reshape(raw_data, [], n_cols);
        return;
    end

    error(['Loaded data column mismatch for %s. config.data_columns has %d entries, ' ...
        'but the loaded array is %d x %d and cannot be reshaped to that width.'], ...
        filename, n_cols, size(raw_data, 1), size(raw_data, 2));
end

function print_input_configuration(input_config, config)
% PRINT_INPUT_CONFIGURATION Report the resolved signal-availability description.

    log_message(config, 1, 'Detected input configuration: %s', ...
        input_config.description);
end
