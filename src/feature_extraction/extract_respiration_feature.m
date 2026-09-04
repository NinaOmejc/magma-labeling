function b = extract_respiration_feature(x, config, basename)
% EXTRACT_RESPIRATION_FEATURE Extract respiratory-cycle features.
%
% Syntax:
%   b = extract_respiration_feature(x, config, basename)
%
% Inputs:
%   x - Respiratory-belt signal.
%   config - Pipeline configuration structure.
%   basename - Name used for diagnostic plot output.
%
% Outputs:
%   b - Respiratory-cycle feature structure.

    if nargin < 3 || isempty(basename)
        basename = '';
    end
    min_num_peaks = 3;

    b = struct();
    b.basename = basename;
    b.ok = false;

    x = x(:);

    if isempty(x) || all(isnan(x)) || ~any(x)
        b.x0 = x;
        b.peak_idx = [];
        b.peak_t = [];
        b.peak_val = [];
        b.trough_idx = [];
        b.trough_t = [];
        b.trough_val = [];
        b.amp = NaN;
        b.ibi = NaN;
        b.rr_bpm = NaN;
        b.rr_mean_bpm = NaN;
        b.rr_std_bpm = NaN;
        return;
    end

    if config.resp.smooth_sec > 0
        x = smoothdata(x, 'movmean', max(1, round(config.resp.smooth_sec*config.fs)));
    end
    b.x0 = x;

    % ---- peaks ----
    [pks, locs, widths, proms] = findpeaks(x, ...
        'MinPeakDistance', max(1, round(config.resp.min_peak_dist_sec*config.fs)), ...
        'MinPeakProminence', config.resp.min_peak_prom, ...
        'MinPeakHeight', config.resp.min_peak_height);

    b.auto_peak_idx = locs(:);
    b.auto_peak_val = pks(:);
    b.auto_peak_width = widths(:);
    b.auto_peak_prom = proms(:);

    [locs, peak_qc] = apply_respiration_peak_qc(locs, proms, config);
    b.peak_qc = peak_qc;

    if numel(locs) < min_num_peaks
        b = recompute_respiration_breath_fields(b, x, locs, config);
        % not enough peaks to define breaths robustly
        return;
    end

    b = recompute_respiration_breath_fields(b, x, locs, config);

    % ---- optional plotting ----
    if isfield(config.resp, 'do_plot') && config.resp.do_plot
        t = (0:length(x)-1) / config.fs;
        figure('Units','pixels','Position', near_fullscreen_figure_position(), 'Visible', config.make_figs_visible); 
        hold on
        h_signal = plot(t, x, 'DisplayName', 'x0');
        h_peak = plot((b.peak_idx - 1) / config.fs, b.peak_val, 'ro', ...
            'MarkerFaceColor', 'r', 'DisplayName', 'peaks');
        h_trough = plot((b.trough_idx - 1) / config.fs, b.trough_val, 'bo', ...
            'MarkerFaceColor', 'b', 'DisplayName', 'troughs');
        title(['RESPIRATION ' basename newline 'Subject: ' num2str(config.subject) ' | Measurement: ' num2str(config.measure)])
        legend_handles = [h_signal; h_peak; h_trough];
        legend_handles = legend_handles(isgraphics(legend_handles));
        legend_labels = get(legend_handles, 'DisplayName');
        if ischar(legend_labels) || isstring(legend_labels)
            legend_labels = cellstr(legend_labels);
        end
        legend(legend_handles, legend_labels, 'Location', 'best')
        ylabel('Standardized respiration belt amplitude')
        xlabel('Time (seconds)')
        hold off
        save_figure(config, basename)
    end
end

function [peak_idx, qc] = apply_respiration_peak_qc(peak_idx, peak_prom, config)
% APPLY_RESPIRATION_PEAK_QC Conservatively remove likely duplicate or split peaks.
%
% Syntax:
%   [peak_idx, qc] = apply_respiration_peak_qc(peak_idx, peak_prom, config)
%
% Inputs:
%   peak_idx - Automatically detected respiratory peak sample indices.
%   peak_prom - Prominence of each automatically detected peak.
%   config - Pipeline configuration structure.
%
% Outputs:
%   peak_idx - Respiratory peak indices retained after conservative QC.
%   qc - Summary of removed peaks and removal reasons.

    peak_idx = peak_idx(:);
    peak_prom = peak_prom(:);
    min_num_peaks = 3;
    qc = struct( ...
        'enabled', false, ...
        'removed_peak_idx', [], ...
        'removed_peak_t', [], ...
        'removed_reason', {{}}, ...
        'reason', 'disabled');

    if ~isfield(config.resp, 'qc') || ~isfield(config.resp.qc, 'enabled') || ~config.resp.qc.enabled
        return;
    end

    qc.enabled = true;
    qc.reason = 'conservative duplicate/split-peak QC using local rhythm and prominence';

    min_prom_ratio = 0.35;
    short_ibi_ratio = 0.65;
    rhythm_merge_tol = 0.35;
    local_window_breaths = 7; % fixed neighborhood for local rhythm and prominence references
    if isfield(config.resp.qc, 'min_prom_ratio'), min_prom_ratio = config.resp.qc.min_prom_ratio; end
    if isfield(config.resp.qc, 'short_ibi_ratio'), short_ibi_ratio = config.resp.qc.short_ibi_ratio; end
    if isfield(config.resp.qc, 'rhythm_merge_tol'), rhythm_merge_tol = config.resp.qc.rhythm_merge_tol; end

    removed_idx = [];
    removed_reason = {};
    max_iter = 5;
    for iter = 1:max_iter
        if numel(peak_idx) < min_num_peaks
            break;
        end

        ibi = diff(peak_idx) / config.fs;
        prom = peak_prom(:);

        remove = false(numel(peak_idx), 1);
        iter_reason = repmat({''}, numel(peak_idx), 1);
        half_win = floor(max(3, local_window_breaths) / 2);
        for i = 1:numel(peak_idx)
            if i > numel(prom) || ~isfinite(prom(i))
                continue;
            end

            lo = max(1, i - half_win);
            hi = min(numel(prom), i + half_win);
            neighbor_idx = lo:hi;
            neighbor_idx(neighbor_idx == i) = [];
            local_prom = prom(neighbor_idx);
            local_prom = local_prom(isfinite(local_prom) & local_prom > 0);
            if isempty(local_prom)
                continue;
            end
            local_prom_ref = median(local_prom, 'omitnan');
            if ~isfinite(local_prom_ref) || local_prom_ref <= 0
                continue;
            end

            ibi_lo = max(1, i - half_win);
            ibi_hi = min(numel(ibi), i + half_win);
            local_ibi = ibi(ibi_lo:ibi_hi);
            local_ibi = local_ibi(isfinite(local_ibi) & local_ibi > 0);
            if isempty(local_ibi)
                continue;
            end
            local_ibi_ref = median(local_ibi, 'omitnan');
            if ~isfinite(local_ibi_ref) || local_ibi_ref <= 0
                continue;
            end

            prev_short = i > 1 && ibi(i-1) < short_ibi_ratio * local_ibi_ref;
            next_short = i <= numel(ibi) && ibi(i) < short_ibi_ratio * local_ibi_ref;
            short_ibi = prev_short || next_short;

            restores_rhythm = false;
            if i > 1 && i <= numel(ibi)
                merged_ibi = ibi(i-1) + ibi(i);
                restores_rhythm = abs(merged_ibi - local_ibi_ref) <= rhythm_merge_tol * local_ibi_ref;
            end

            low_prom = prom(i) < min_prom_ratio * local_prom_ref;

            if short_ibi && (restores_rhythm || low_prom)
                remove(i) = true;
                reason_parts = {'short_ibi'};
                if restores_rhythm, reason_parts{end+1} = 'rhythm'; end %#ok<AGROW>
                if low_prom, reason_parts{end+1} = 'low_prominence'; end %#ok<AGROW>
                iter_reason{i} = strjoin(reason_parts, '+');
            end
        end

        if ~any(remove)
            break;
        end

        removed_idx = [removed_idx; peak_idx(remove)]; %#ok<AGROW>
        removed_reason = [removed_reason; iter_reason(remove)]; %#ok<AGROW>
        peak_idx = peak_idx(~remove);
        peak_prom = peak_prom(~remove);
    end

    qc.removed_peak_idx = removed_idx;
    qc.removed_peak_t = (removed_idx - 1) / config.fs;
    qc.removed_reason = removed_reason;
end
