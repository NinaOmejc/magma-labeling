function baseline = compute_baseline(data, config)
% compute_baseline  Compute baseline stats from the configured static segment.
% Baseline definitions follow Labels.docx (e.g., SpO2 median over the configured static segment). :contentReference[oaicite:1]{index=1}
% Baseline is required for labels:
%   1) Shallow breathing ( respiratory belt signals  amplitude baseline (lungs, diaphragm))
%   6) Desaturation (SpO2 baseline: median of the static segment)
%   7) Apnea (respiratory belt signals amplitude baseline (lungs, diaphragm) )
%
% baseline = compute_baseline(data, fs, columns, baseline_sec)

    idxSpO2 = find(strcmp(config.data_columns, 'SpO₂'), 1);
    idxLungs = find(strcmp(config.data_columns, 'Resp-Lungs'), 1);
    idxDiaph = find(strcmp(config.data_columns, 'Resp-Diaphragm'), 1);
    
    baseline = struct();
    [baseline_start_idx, baseline_end_idx, baseline_start_t, baseline_end_t] = ...
        get_static_baseline_interval(size(data,1), config);
    d0 = data(baseline_start_idx:baseline_end_idx, :);

    baseline.static_baseline_start_idx = baseline_start_idx;
    baseline.static_baseline_end_idx = baseline_end_idx;
    baseline.static_baseline_start_t = baseline_start_t;
    baseline.static_baseline_end_t = baseline_end_t;
    baseline.static_baseline_location = '';
    if isfield(config, 'baseline_location')
        baseline.static_baseline_location = config.baseline_location;
    end
    baseline.SpO2_baseline_start_idx = baseline_start_idx;
    baseline.SpO2_baseline_end_idx = baseline_end_idx;
    baseline.SpO2_baseline_start_t = baseline_start_t;
    baseline.SpO2_baseline_end_t = baseline_end_t;

    % SpO2 baseline: median of the configured static segment.
    if ~isempty(idxSpO2)
        baseline.SpO2_median = median(d0(:, idxSpO2), 'omitnan');
        baseline.SpO2_mean   = mean(d0(:, idxSpO2), 'omitnan');
    else
        baseline.SpO2_median = NaN;
        baseline.SpO2_mean   = NaN;
    end

    % Respiratory reference amplitude: robust cycle amplitude from baseline segment
    [baseline.lungs_amp_ref, baseline.lungs_rr_ref] = resp_amp_ref_from_segment(d0(:, idxLungs), config, 'baseline-lungs');
    [baseline.diaph_amp_ref, baseline.diaph_rr_ref] = resp_amp_ref_from_segment(d0(:, idxDiaph), config, 'baseline-diaph');

end

function [amp_ref, rr_ref, b] = resp_amp_ref_from_segment(x, config, basename)
% resp_amp_ref_from_segment
% Computes a robust amplitude reference and RR reference from a baseline segment.

    b = extract_respiration_feature(x, config, basename);

    if ~b.ok
        amp_ref = NaN;
        rr_ref  = NaN;
        return;
    end

    amp_ref = median(b.amp, 'omitnan');
    rr_ref  = b.rr_mean_bpm;
end
