function [b_l, b_d] = extract_respiration_features(data, baseline, config)
    
    idx_lungs = find(strcmp(config.data_columns, 'Resp-Lungs'), 1);
    idx_diaph  = find(strcmp(config.data_columns, 'Resp-Diaphragm'), 1);

    % ---- breath series (peaks + per-breath amplitudes) ----
    b_l = extract_respiration_feature(data(:, idx_lungs), config, 'lungs');
    b_d = extract_respiration_feature(data(:, idx_diaph), config, 'diaph');
    
    if ~ismember(config.subject, config.problems.subjects_with_broken_lung_belt)
        b_l_normality = check_normalities(b_l, config);
    end
    b_d_normality = check_normalities(b_d, config);
 end
