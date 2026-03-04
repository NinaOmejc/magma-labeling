function [b_l, b_d] = extract_respiration_features(data, baseline, config)
    
    idx_lungs = find(strcmp(config.data_columns, 'Resp-Lungs'), 1);
    idx_diap  = find(strcmp(config.data_columns, 'Resp-Diaphragm'), 1);

    if ~isfinite(baseline.lungs_amp_ref) || baseline.lungs_amp_ref <= 0 || ...
       ~isfinite(baseline.diap_amp_ref)  || baseline.diap_amp_ref  <= 0
        return;
    end

    % ---- breath series (peaks + per-breath amplitudes) ----
    b_l = extract_respiration_feature(data(:, idx_lungs), config, 'lungs');
    b_d = extract_respiration_feature(data(:, idx_diap),  config, 'diaph');
end
