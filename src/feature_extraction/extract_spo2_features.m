function spo2_feat = extract_spo2_features(data, spo2_ref, config)
% extract_spo2_features
% Extract SpO2 on the config.fs master timeline and detect Label 11 events
% relative to the modality-specific statistic from the common session
% physiological reference interval.

    if ~isfield(config, 'channels')
        config = resolve_signal_channels(config);
    end

    spo2_feat = struct();
    spo2_feat.idx_spo2 = config.channels.spo2_idx;
    spo2_feat.signal_available = false;
    spo2_feat.reference_available = false;
    spo2_feat.reference_quality = 'not_evaluated';
    spo2_feat.detection_available = false;

    if isempty(spo2_feat.idx_spo2)
        spo2_feat.t_spo2 = [];
        spo2_feat.spo2 = [];
        spo2_feat.desat_events = empty_events();
        spo2_feat.is_desat_samples = [];
        return;
    end

    spo2_feat.spo2 = data(:, spo2_feat.idx_spo2);
    spo2_feat.t_spo2 = (0:numel(spo2_feat.spo2)-1) / config.fs;
    spo2_feat.signal_available = nnz(isfinite(spo2_feat.spo2)) >= 2;
    spo2_feat.reference_available = isstruct(spo2_ref) && ...
        isfield(spo2_ref, 'available') && logical(spo2_ref.available) && ...
        isfield(spo2_ref, 'median_percent') && isfinite(spo2_ref.median_percent);
    if isstruct(spo2_ref) && isfield(spo2_ref, 'quality')
        spo2_feat.reference_quality = char(string(spo2_ref.quality));
    end
    spo2_feat.detection_available = spo2_feat.signal_available && ...
        spo2_feat.reference_available;

    if ~spo2_feat.detection_available
        spo2_feat.desat_events = empty_events();
        spo2_feat.is_desat_samples = false(size(spo2_feat.spo2));
        return;
    end

    floor_thr = 90;
    drop_thr = 3;
    min_dur_sec = 10;

    if isfield(config, 'spo2')
        if isfield(config.spo2, 'spo2_floor'), floor_thr = config.spo2.spo2_floor; end
        if isfield(config.spo2, 'drop_thr'), drop_thr = config.spo2.drop_thr; end
        if isfield(config.spo2, 'min_dur_sec'), min_dur_sec = config.spo2.min_dur_sec; end
    end

    spo2_feat.desat_events = detect_desaturation_events( ...
        spo2_feat.spo2, spo2_ref.median_percent, config.fs, ...
        floor_thr, drop_thr, min_dur_sec);

    spo2_feat.is_desat_samples = events_to_sample_mask( ...
        spo2_feat.desat_events, numel(spo2_feat.spo2), config.fs);
end

function desat_events = detect_desaturation_events(spo2, spo2_base, fs, spo2_floor, drop_thr, min_dur_sec)
% detect_desaturation_events  Detect sustained SpO2 desaturation episodes.

    desat_events = empty_events();

    if nargin < 6 || isempty(min_dur_sec), min_dur_sec = 10; end
    if nargin < 5 || isempty(drop_thr), drop_thr = 3; end
    if nargin < 4 || isempty(spo2_floor), spo2_floor = 90; end

    if isempty(spo2) || all(isnan(spo2)) || ~isfinite(spo2_base) || ~isfinite(fs) || fs <= 0
        return;
    end

    spo2 = spo2(:);
    N = numel(spo2);

    is_desat = false(N, 1);
    valid = isfinite(spo2);
    is_desat(valid) = (spo2(valid) < spo2_floor) | ((spo2_base - spo2(valid)) >= drop_thr);

    desat_events = runs_to_events(is_desat, fs, min_dur_sec, 'desaturation');
end
