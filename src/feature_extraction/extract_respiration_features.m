function [b_l, b_d] = extract_respiration_features(data, ~, config)
    
    idx_lungs = find(strcmp(config.data_columns, 'Resp-Lungs'), 1);
    idx_diaph  = find(strcmp(config.data_columns, 'Resp-Diaphragm'), 1);

    % ---- breath series (peaks + per-breath amplitudes) ----
    b_l = extract_respiration_feature(data(:, idx_lungs), config, 'lungs');
    b_d = extract_respiration_feature(data(:, idx_diaph), config, 'diaph');

    if isfield(config.resp, 'manual_control') && config.resp.manual_control
        [b_l, b_d] = manual_edit_respiration_features(data, b_l, b_d, config);
    end
    
    if ~ismember(config.subject, config.problems.subjects_with_broken_lung_belt)
        check_normalities(b_l, config);
    end
    check_normalities(b_d, config);
end
