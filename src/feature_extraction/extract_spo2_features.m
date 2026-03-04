function spo2_feat = extract_spo2_features(data, baseline, config)
% extract_spo2_features
% Extracts SpO2 signal and detects desaturation events (Label 6) once.
%
% Output fields:
%   spo2_feat.idx_spo2
%   spo2_feat.t_spo2
%   spo2_feat.spo2
%   spo2_feat.desat_events          (Label 6 canonical)
%   spo2_feat.is_desat_samples      (logical, sample-level)
%
% Uses baseline.SpO2_median as baseline (median first 60s).

    spo2_feat = struct();
    spo2_feat.idx_spo2 = find(strcmp(config.data_columns, 'SpO₂'), 1);

    if isempty(spo2_feat.idx_spo2)
        spo2_feat.t_spo2 = [];
        spo2_feat.spo2 = [];
        spo2_feat.desat_events = empty_events();
        spo2_feat.is_desat_samples = [];
        return;
    end

    spo2_feat.spo2 = data(:, spo2_feat.idx_spo2);
    spo2_feat.t_spo2 = (0:numel(spo2_feat.spo2)-1) / config.fs;

    if ~isfield(baseline, 'SpO2_median') || ~isfinite(baseline.SpO2_median)
        spo2_feat.desat_events = empty_events();
        spo2_feat.is_desat_samples = false(size(spo2_feat.spo2));
        return;
    end

    % thresholds (Label 6)
    floor_thr    = 90;
    drop_thr     = 3;
    min_dur_sec  = 10;

    if isfield(config, 'spo2')
        if isfield(config.spo2, 'spo2_floor'),      floor_thr   = config.spo2.spo2_floor; end
        if isfield(config.spo2, 'drop_thr'),        drop_thr    = config.spo2.drop_thr; end
        if isfield(config.spo2, 'min_dur_sec'),     min_dur_sec = config.spo2.min_dur_sec; end
    end

    spo2_feat.desat_events = detect_desaturation_events( ...
        spo2_feat.spo2, baseline.SpO2_median, config.fs, floor_thr, drop_thr, min_dur_sec);

    spo2_feat.is_desat_samples = events_to_sample_mask(spo2_feat.desat_events, numel(spo2_feat.spo2), config.fs);
end


function desat_events = detect_desaturation_events(spo2, spo2_base, fs, spo2_floor, drop_thr, min_dur_sec)
% detect_desaturation_events
% Label 6 helper: detect SpO2 desaturation episodes.
%
% Episode criteria:
%   is_desat = (SpO2 < spo2_floor) OR ((spo2_base - SpO2) >= drop_thr)
%   and sustained for >= min_dur_sec seconds (continuous samples).
%
% Inputs:
%   spo2        [N x 1] SpO2 signal (can include NaNs)
%   spo2_base   scalar baseline (e.g., median of first 60s)
%   fs          sampling frequency (Hz)
%   spo2_floor  absolute threshold (default 90)
%   drop_thr    relative drop from baseline (default 3)
%   min_dur_sec minimum episode duration in seconds (default 10)
%
% Output:
%   desat_events struct array with fields:
%     type, start_idx, end_idx, start_t, end_t

    desat_events = empty_events();

    if nargin < 6 || isempty(min_dur_sec), min_dur_sec = 10; end
    if nargin < 5 || isempty(drop_thr),    drop_thr = 3; end
    if nargin < 4 || isempty(spo2_floor),  spo2_floor = 90; end

    if isempty(spo2) || all(isnan(spo2)) || ~isfinite(spo2_base) || ~isfinite(fs) || fs <= 0
        return;
    end

    spo2 = spo2(:);
    N = numel(spo2);

    % Define desaturation samples. Treat NaNs as "not desat" (conservative).
    is_desat = false(N,1);
    valid = isfinite(spo2);

    is_desat(valid) = (spo2(valid) < spo2_floor) | ((spo2_base - spo2(valid)) >= drop_thr);

    % Convert contiguous runs of is_desat -> events, enforce duration
    d = diff([false; is_desat; false]);
    run_starts = find(d == 1);
    run_ends   = find(d == -1) - 1;
    joined_runs = [run_starts, run_ends, run_ends - run_starts];
    min_len = max(1, round(min_dur_sec * fs));

    for k = 1:numel(run_starts)
        s = run_starts(k);
        e = run_ends(k);

        if (e - s + 1) < min_len
            continue;
        end

        desat_events(end+1,1) = struct( ...
            'type',      'desaturation', ...
            'start_idx', s, ...
            'end_idx',   e, ...
            'start_t',   (s-1)/fs, ...
            'end_t',     (e-1)/fs );
    end
end