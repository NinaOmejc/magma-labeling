function baseline = add_rolling_resp_baseline(baseline, breaths_lungs, breaths_diaph, N, config)
% add_rolling_resp_baseline
% Adds time-varying respiratory amplitude references to baseline.

if ~isfield(config, 'rolling_baseline') || ~config.rolling_baseline.enabled
    return;
end

t_grid = (0:config.grid_step_sec:(N-1)/config.fs)';

win_sec = config.rolling_baseline.win_sec;
lag_sec = config.rolling_baseline.lag_sec;
min_breaths = config.rolling_baseline.min_breaths;
method = config.rolling_baseline.method;

baseline.rolling = struct();
baseline.rolling.t_grid = t_grid;

baseline.rolling.lungs_amp_ref = rolling_amp_ref( ...
    breaths_lungs, t_grid, win_sec, lag_sec, min_breaths, ...
    method, baseline.lungs_amp_ref);

baseline.rolling.diap_amp_ref = rolling_amp_ref( ...
    breaths_diaph, t_grid, win_sec, lag_sec, min_breaths, ...
    method, baseline.diap_amp_ref);

end

function ref = rolling_amp_ref(breaths, t_grid, win_sec, lag_sec, min_breaths, method, fallback_ref)

ref = nan(size(t_grid));

if isempty(breaths) || ~isstruct(breaths) || ~isfield(breaths, 'peak_t') || ...
        ~isfield(breaths, 'amp') || ~isfield(breaths, 'ok') || ~breaths.ok
    ref(:) = fallback_ref;
    return;
end

peak_t = breaths.peak_t(:);
amp = breaths.amp(:);

L = min(numel(peak_t), numel(amp));
peak_t = peak_t(1:L);
amp = amp(1:L);

valid = isfinite(peak_t) & isfinite(amp) & amp > 0;
peak_t = peak_t(valid);
amp = amp(valid);

for i = 1:numel(t_grid)
    t = t_grid(i);

    t2 = t - lag_sec;
    t1 = t2 - win_sec;

    if t2 <= 0
        ref(i) = fallback_ref;
        continue;
    end

    in_win = peak_t >= t1 & peak_t <= t2;
    amps = amp(in_win);

    if numel(amps) < min_breaths
        ref(i) = fallback_ref;
        continue;
    end

    switch lower(method)
        case 'median'
            ref(i) = median(amps, 'omitnan');
        case 'p75'
            ref(i) = prctile(amps, 75);
        otherwise
            error('Unknown rolling baseline method: %s', method);
    end
end

bad = ~isfinite(ref) | ref <= 0;
ref(bad) = fallback_ref;

end
