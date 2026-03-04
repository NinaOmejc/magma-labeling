function b = extract_respiration_feature(x, config, basename)
% resp_extract_breaths
% Unified respiration breath extraction:
% - detrends (robustly)
% - finds peaks (breaths)
% - finds troughs between peaks (robust, percentile-based by default)
% - returns per-breath amplitudes, peak/trough indices, RR (respiratory rate) and IBI (time between breaths in seconds)
%
% Output struct b fields:
%   b.x0                detrended signal
%   b.peak_idx, b.peak_t, b.peak_val
%   b.trough_idx, b.trough_t, b.trough_val     (between peak i and i+1)
%   b.amp                                   (peak(i) - trough(i)) length n_peaks-1
%   b.ibi_s                                 inter-breath intervals (seconds)
%   b.rr_bpm                                instantaneous RR per interval (bpm)
%   b.rr_mean_bpm                           mean RR in segment
%   b.ok                                   true if enough peaks found
%
% Notes:
% - For amplitude, we compute trough in each interval [peak(i), peak(i+1)].
% - Use params.trough_method = 'min' or 'prctile' (default).
%
% Usage:
%   params = resp_default_params(fs);
%   b = resp_extract_breaths(x, fs, params);
    
    if nargin < 3 || isempty(basename)
        basename = '';
    end

    b = struct();
    b.ok = false;

    if isempty(x) || all(isnan(x))
        return;
    end

    x = x(:);

    % ---- detrend (robust) ----
    x0 = x - median(x, 'omitnan');
    if config.resp.smooth_sec > 0
        x0 = smoothdata(x0, 'movmean', max(1, round(config.resp.smooth_sec*config.fs)));
    end
    b.x0 = x0;

    % ---- peaks ----
    [pks, locs] = findpeaks(x0, ...
        'MinPeakDistance', max(1, round(config.resp.min_peak_dist_sec*config.fs)), ...
        'MinPeakProminence', config.resp.min_peak_prom);

    b.peak_idx = locs(:);
    b.peak_t   = (locs(:)-1)/config.fs;
    b.peak_val = pks(:);

    if numel(locs) < config.resp.min_num_peaks
        % not enough peaks to define breaths robustly
        return;
    end

    % ---- troughs between peaks ----
    n = numel(locs);
    trough_idx = zeros(n-1, 1);
    trough_val = zeros(n-1, 1);
    amp        = zeros(n-1, 1);

    for i = 1:n-1
        idx_range = locs(i):locs(i+1);
        seg = x0(idx_range);

        switch lower(config.resp.trough_method)
            case 'min'
                [tr, j] = min(seg);

            case 'prctile'
                tr_p = prctile(seg, config.resp.trough_prct);
                % choose sample closest to percentile value
                [~, j] = min(abs(seg - tr_p));
                tr = seg(j);

            otherwise
                error('Unknown params.trough_method: %s', config.resp.trough_method);
        end

        trough_idx(i) = idx_range(j);
        trough_val(i) = tr;

        amp(i) = pks(i) - tr;   % amplitude associated with peak i
    end

    b.trough_idx = trough_idx;
    b.trough_t   = (trough_idx-1)/config.fs;
    b.trough_val = trough_val;

    b.amp = [amp(:); NaN];

    % ---- IBI / RR ----
    ibi = diff(locs) / config.fs; % time between breaths
    b.ibi_s = ibi(:);
    b.rr_bpm = 60 ./ b.ibi_s; % convert to seconds per breath to breats per minute
    b.rr_mean_bpm = 60 / mean(b.ibi_s, 'omitnan');
    b.rr_std_bpm = std(b.rr_bpm, 'omitnan');
    b.ok = true;

    % ---- optional plotting ----
    if isfield(config.resp, 'do_plot') && config.resp.do_plot
        figure('Units','pixels','Position',[100 100 1200 800], 'Visible', config.make_figs_visible); 
        hold on
        plot(x0)
        plot(b.peak_idx, b.peak_val, 'ro', 'MarkerFaceColor', 'r')
        plot(b.trough_idx, b.trough_val, 'bo', 'MarkerFaceColor', 'b')
        title(['RESPIRATION' newline 'Subject: ' num2str(config.subject) ' | Condition: ' num2str(config.condition)])
        legend('x0', 'peaks', 'troughs')
        hold off
        save_figure(config, basename)
    end
end




