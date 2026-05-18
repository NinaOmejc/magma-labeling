function [data, config, do_analysis] = load_raw_data(config)

    % PREPARE OUTPUT FOLDER
    config.sub_results_path = [config.path_results_out filesep 'Sub' num2str(config.subject) '_M' num2str(config.measure)];
    config.sub_results_filename = ['Sub' num2str(config.subject) '_M' num2str(config.measure) '_labels.mat'];
    config.sub_features_filename = ['Sub' num2str(config.subject) '_M' num2str(config.measure) '_features.mat'];

    do_analysis = true;
    if isfolder(config.sub_results_path) && exist([config.sub_results_path filesep config.sub_results_filename] , 'file')
        if config.overwrite_results
            do_analysis = true;
            disp(['Overwritting analysis for: Sub ' num2str(config.subject) ' | Measurement: ' num2str(config.measure) ])
        else
            do_analysis = false;
            data = [];
            disp(['Skipping analysis, as results already exist: Sub ' num2str(config.subject) ' | Measurement: ' num2str(config.measure) ])
            return
        end
    else
        if ~isfolder(config.sub_results_path)
            mkdir(config.sub_results_path);
        end
        disp(['Successfully loaded data: Sub ' num2str(config.subject) ' | Measurement: ' num2str(config.measure) ])
    end

    % LOAD DATA
    filename = ['ECG1_ECG2_SpO2_RespL_BP_RespD_fs200_Sub' num2str(config.subject) '_Pom' num2str(config.measure) '_DeTr_Norm.dat'];
    data = load([config.path_data_in filesep filename]);
    data = reshape(data, [], 6);
    
    % CHECK PROBLEMS
    if any(config.subject == config.problems.subjects_with_broken_lung_belt)
        lung_idx = find(ismember(config.data_columns, 'Resp-Lungs'));
        data(:, lung_idx) = data(:, lung_idx) * 0;
    end

    % CALCULATE TIMES
    config.times = (0:size(data,1)-1)/config.fs;

    % PLOT RAW DATA
    plot_raw_data(data, config);
    
end

