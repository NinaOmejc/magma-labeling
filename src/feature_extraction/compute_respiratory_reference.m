function resp_ref = compute_respiratory_reference(resp_feat, config)
% compute_respiratory_reference
% Diagnose whether reviewed breath amplitudes support one stable reference
% or one persistent step-like change. This result is diagnostic only and is
% not used by label detectors.

    cfg = respiratory_reference_config(config);

    lungs = get_belt_features(resp_feat, 'lungs');
    if is_lung_belt_ignored(config)
        lungs = [];
    end

    resp_ref = struct();
    resp_ref.lungs = analyze_belt(lungs, cfg);
    resp_ref.diaph = analyze_belt(get_belt_features(resp_feat, 'diaph'), cfg);
    resp_ref = add_belt_agreement(resp_ref, cfg);
end

function belt = analyze_belt(breaths, cfg)
    belt = empty_belt_reference();
    if isempty(breaths) || ~isstruct(breaths) || ...
            ~isfield(breaths, 'peak_t') || ~isfield(breaths, 'amp')
        return;
    end

    peak_t = breaths.peak_t(:);
    amp = breaths.amp(:);
    n_input = min(numel(peak_t), numel(amp));
    peak_t = peak_t(1:n_input);
    amp = amp(1:n_input);
    input_idx = (1:n_input)';

    valid = isfinite(peak_t) & isfinite(amp) & amp > 0;
    belt.n_input_breaths = n_input;
    belt.n_valid_breaths = nnz(valid);
    belt.n_invalid_breaths = n_input - belt.n_valid_breaths;
    belt.available = belt.n_valid_breaths > 0;

    if belt.n_valid_breaths < 2 * cfg.min_segment_breaths
        return;
    end

    peak_t = peak_t(valid);
    amp = amp(valid);
    input_idx = input_idx(valid);
    [peak_t, order] = sort(peak_t, 'ascend');
    amp = amp(order);
    input_idx = input_idx(order);

    duration_sec = peak_t(end) - peak_t(1);
    if ~isfinite(duration_sec) || duration_sec <= 0
        return;
    end

    % Keep the two edge regions disjoint for recordings shorter than twice
    % the configured edge window.
    belt.edge_window_sec_used = min(cfg.edge_window_sec, 0.25 * duration_sec);
    early = peak_t <= peak_t(1) + belt.edge_window_sec_used;
    late = peak_t >= peak_t(end) - belt.edge_window_sec_used;
    if nnz(early) < cfg.min_segment_breaths || nnz(late) < cfg.min_segment_breaths
        belt.quality = 'insufficient_edge_breaths';
        return;
    end

    belt.start_ref = median(amp(early), 'omitnan');
    belt.end_ref = median(amp(late), 'omitnan');
    belt.single_ref = median(amp, 'omitnan');
    belt.end_to_start_ratio = belt.end_ref / belt.start_ref;
    belt.log_change = log(belt.end_to_start_ratio);
    belt.edge_change_frac = symmetric_fractional_change(belt.end_to_start_ratio);
    belt.edge_change_triggered = belt.edge_change_frac >= cfg.change_trigger_frac;

    if ~belt.edge_change_triggered
        belt.mode = 'single';
        belt.quality = 'good';
        return;
    end

    z = log(amp);
    candidate = best_single_change_candidate(z, cfg.min_segment_breaths);
    if ~candidate.available
        belt.mode = 'single';
        belt.quality = 'edge_disagreement_no_step';
        return;
    end

    % Retain the best inspected split for traceability even when the
    % acceptance guards below reject it as a persistent sharp change.
    belt.change_breath_idx = input_idx(candidate.split_idx + 1);
    belt.change_t = peak_t(candidate.split_idx + 1);
    belt.ref_before = exp(candidate.level_before);
    belt.ref_after = exp(candidate.level_after);
    belt.change_ratio = belt.ref_after / belt.ref_before;
    belt.cost_improvement = candidate.cost_improvement;
    belt.step_sharpness = candidate.step_sharpness;
    belt.residual_drift_log = candidate.residual_drift_log;
    belt.persistence_ok = candidate.persistence_ok;

    candidate_change_frac = symmetric_fractional_change(belt.change_ratio);
    magnitude_ok = candidate_change_frac >= cfg.change_trigger_frac;
    cost_ok = candidate.cost_improvement >= cfg.min_cost_improvement;

    % Internal shape guards distinguish a localized, persistent step from a
    % smooth drift or unresolved multi-regime behavior. They are diagnostic
    % safeguards, not physiological thresholds.
    sharpness_ok = candidate.step_sharpness >= 0.60;
    drift_ok = candidate.residual_drift_log <= candidate.drift_limit_log;
    belt.change_detected = magnitude_ok && cost_ok && sharpness_ok && ...
        drift_ok && candidate.persistence_ok;

    if belt.change_detected
        belt.mode = 'change_candidate';
        belt.quality = 'good';
    elseif ~magnitude_ok || ~cost_ok
        belt.mode = 'single';
        belt.quality = 'edge_disagreement_no_step';
    else
        belt.mode = 'single';
        belt.quality = 'gradual_or_complex';
    end
end

function candidate = best_single_change_candidate(z, min_segment_breaths)
    candidate = struct( ...
        'available', false, ...
        'split_idx', NaN, ...
        'level_before', NaN, ...
        'level_after', NaN, ...
        'cost_improvement', NaN, ...
        'step_sharpness', NaN, ...
        'residual_drift_log', NaN, ...
        'drift_limit_log', NaN, ...
        'persistence_ok', false);

    n = numel(z);
    one_level = median(z, 'omitnan');
    one_level_cost = sum(abs(z - one_level), 'omitnan');
    if ~isfinite(one_level_cost) || one_level_cost <= eps(max(abs(z)))
        return;
    end

    best_cost = inf;
    for k = min_segment_breaths:n-min_segment_breaths
        level_before = median(z(1:k), 'omitnan');
        level_after = median(z(k+1:end), 'omitnan');
        cost = sum(abs(z(1:k) - level_before), 'omitnan') + ...
            sum(abs(z(k+1:end) - level_after), 'omitnan');
        if cost < best_cost
            best_cost = cost;
            candidate.available = true;
            candidate.split_idx = k;
            candidate.level_before = level_before;
            candidate.level_after = level_after;
        end
    end

    if ~candidate.available
        return;
    end

    candidate.cost_improvement = max(0, (one_level_cost - best_cost) / one_level_cost);
    k = candidate.split_idx;
    delta = abs(candidate.level_after - candidate.level_before);

    local_n = min([min_segment_breaths, k, n-k]);
    local_before = median(z(k-local_n+1:k), 'omitnan');
    local_after = median(z(k+1:k+local_n), 'omitnan');
    candidate.step_sharpness = abs(local_after - local_before) / max(delta, eps);

    drift_before = segment_edge_change(z(1:k));
    drift_after = segment_edge_change(z(k+1:end));
    candidate.residual_drift_log = max(drift_before, drift_after);

    dz = diff(z);
    dz_center = median(dz, 'omitnan');
    local_noise = 1.4826 * median(abs(dz - dz_center), 'omitnan') / sqrt(2);
    if ~isfinite(local_noise)
        local_noise = 0;
    end
    candidate.drift_limit_log = 0.35 * delta + 2 * local_noise;

    post = z(k+1:end);
    tail_n = min(numel(post), max(min_segment_breaths, floor(numel(post) / 3)));
    tail_level = median(post(end-tail_n+1:end), 'omitnan');
    direction = sign(candidate.level_after - candidate.level_before);
    midpoint = 0.5 * (candidate.level_before + candidate.level_after);
    tail_on_after_side = direction * (tail_level - midpoint) > 0;
    tail_stable = abs(tail_level - candidate.level_after) <= ...
        0.35 * delta + 2 * local_noise;
    candidate.persistence_ok = direction ~= 0 && tail_on_after_side && tail_stable;
end

function d = segment_edge_change(z)
    edge_n = max(1, floor(numel(z) / 3));
    first_level = median(z(1:edge_n), 'omitnan');
    last_level = median(z(end-edge_n+1:end), 'omitnan');
    d = abs(last_level - first_level);
end

function value = symmetric_fractional_change(ratio)
    if ~isfinite(ratio) || ratio <= 0
        value = NaN;
    else
        value = max(ratio, 1 / ratio) - 1;
    end
end

function resp_ref = add_belt_agreement(resp_ref, cfg)
    resp_ref.change_pattern = 'insufficient_data';
    resp_ref.change_time_difference_sec = NaN;
    resp_ref.change_ratio_log_difference = NaN;
    resp_ref.agreement_quality = 'insufficient_data';

    lungs_ok = belt_is_analyzable(resp_ref.lungs);
    diaph_ok = belt_is_analyzable(resp_ref.diaph);
    if ~(lungs_ok && diaph_ok)
        return;
    end

    lungs_change = resp_ref.lungs.change_detected;
    diaph_change = resp_ref.diaph.change_detected;
    if ~lungs_change && ~diaph_change
        resp_ref.change_pattern = 'none';
        if strcmp(resp_ref.lungs.quality, 'good') && strcmp(resp_ref.diaph.quality, 'good')
            resp_ref.agreement_quality = 'good';
        else
            resp_ref.agreement_quality = 'ambiguous_reference';
        end
    elseif lungs_change && ~diaph_change
        resp_ref.change_pattern = 'lungs_only';
        resp_ref.agreement_quality = 'belt_disagreement';
    elseif ~lungs_change && diaph_change
        resp_ref.change_pattern = 'diaph_only';
        resp_ref.agreement_quality = 'belt_disagreement';
    else
        resp_ref.change_time_difference_sec = abs(resp_ref.lungs.change_t - resp_ref.diaph.change_t);
        resp_ref.change_ratio_log_difference = abs( ...
            log(resp_ref.lungs.change_ratio) - log(resp_ref.diaph.change_ratio));
        time_tolerance = 0.25 * cfg.edge_window_sec;
        ratio_tolerance = log(1 + cfg.change_trigger_frac);
        same_direction = sign(log(resp_ref.lungs.change_ratio)) == ...
            sign(log(resp_ref.diaph.change_ratio));
        similar = same_direction && ...
            resp_ref.change_time_difference_sec <= time_tolerance && ...
            resp_ref.change_ratio_log_difference <= ratio_tolerance;
        if similar
            resp_ref.change_pattern = 'both_similar';
            resp_ref.agreement_quality = 'good';
        else
            resp_ref.change_pattern = 'both_different';
            resp_ref.agreement_quality = 'belt_disagreement';
        end
    end
end

function tf = belt_is_analyzable(belt)
    tf = belt.available && ~strcmp(belt.quality, 'insufficient_data') && ...
        ~strcmp(belt.quality, 'insufficient_edge_breaths');
end

function breaths = get_belt_features(resp_feat, name)
    breaths = [];
    if isstruct(resp_feat) && isfield(resp_feat, name)
        breaths = resp_feat.(name);
    end
end

function belt = empty_belt_reference()
    belt = struct( ...
        'available', false, ...
        'mode', 'insufficient_data', ...
        'quality', 'insufficient_data', ...
        'start_ref', NaN, ...
        'end_ref', NaN, ...
        'single_ref', NaN, ...
        'end_to_start_ratio', NaN, ...
        'log_change', NaN, ...
        'edge_change_frac', NaN, ...
        'edge_change_triggered', false, ...
        'change_detected', false, ...
        'change_breath_idx', NaN, ...
        'change_t', NaN, ...
        'ref_before', NaN, ...
        'ref_after', NaN, ...
        'change_ratio', NaN, ...
        'cost_improvement', NaN, ...
        'step_sharpness', NaN, ...
        'residual_drift_log', NaN, ...
        'persistence_ok', false, ...
        'n_input_breaths', 0, ...
        'n_valid_breaths', 0, ...
        'n_invalid_breaths', 0, ...
        'edge_window_sec_used', NaN);
end

function cfg = respiratory_reference_config(config)
    cfg = struct( ...
        'edge_window_sec', 300, ...
        'change_trigger_frac', 0.25, ...
        'min_segment_breaths', 12, ...
        'min_cost_improvement', 0.30);
    if isfield(config, 'resp_ref')
        names = fieldnames(cfg);
        for i = 1:numel(names)
            if isfield(config.resp_ref, names{i})
                cfg.(names{i}) = config.resp_ref.(names{i});
            end
        end
    end

    if ~isscalar(cfg.edge_window_sec) || ~isfinite(cfg.edge_window_sec) || cfg.edge_window_sec <= 0
        error('config.resp_ref.edge_window_sec must be positive and finite.');
    end
    if ~isscalar(cfg.change_trigger_frac) || ~isfinite(cfg.change_trigger_frac) || cfg.change_trigger_frac <= 0
        error('config.resp_ref.change_trigger_frac must be positive and finite.');
    end
    if ~isscalar(cfg.min_segment_breaths) || ~isfinite(cfg.min_segment_breaths) || ...
            cfg.min_segment_breaths < 3 || cfg.min_segment_breaths ~= round(cfg.min_segment_breaths)
        error('config.resp_ref.min_segment_breaths must be an integer of at least 3.');
    end
    if ~isscalar(cfg.min_cost_improvement) || ~isfinite(cfg.min_cost_improvement) || ...
            cfg.min_cost_improvement < 0 || cfg.min_cost_improvement > 1
        error('config.resp_ref.min_cost_improvement must be between 0 and 1.');
    end
end
