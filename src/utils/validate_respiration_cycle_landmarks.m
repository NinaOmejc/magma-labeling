function [ok, message, issue] = validate_respiration_cycle_landmarks(b)
% VALIDATE_RESPIRATION_CYCLE_LANDMARKS Check peak/trough cycle ordering.
% Empty or single-peak belts are valid when they have no troughs. For a belt
% with two or more peaks, each trough sample (and each supplied finite trough
% time) must lie strictly inside its corresponding adjacent peak pair.

    ok = true;
    message = '';
    issue = empty_issue();
    if ~isstruct(b) || ~isscalar(b)
        [ok, message, issue] = invalid( ...
            'Respiratory landmarks must be stored in a scalar struct.', ...
            'belt_schema', NaN, NaN, NaN, NaN);
        return;
    end

    peak_idx = field_column(b, 'peak_idx');
    trough_idx = field_column(b, 'trough_idx');
    if isempty(peak_idx)
        if ~isempty(trough_idx)
            [ok, message, issue] = invalid( ...
                'Trough samples are present without any peak samples.', ...
                'trough_count', NaN, NaN, NaN, NaN);
        end
        return;
    end
    if ~isnumeric(peak_idx) || any(~isfinite(peak_idx)) || ...
            any(peak_idx ~= round(peak_idx)) || any(peak_idx < 1) || ...
            any(diff(peak_idx) <= 0)
        [ok, message, issue] = invalid( ...
            'Peak samples must be finite, positive, integer, and strictly increasing.', ...
            'peak_idx', NaN, NaN, NaN, NaN);
        return;
    end

    n_intervals = max(numel(peak_idx) - 1, 0);
    if numel(trough_idx) ~= n_intervals
        [ok, message, issue] = invalid(sprintf( ...
            'Expected %d inter-peak trough samples but found %d.', ...
            n_intervals, numel(trough_idx)), ...
            'trough_count', NaN, NaN, NaN, NaN);
        return;
    end
    if n_intervals == 0
        return;
    end
    if ~isnumeric(trough_idx) || any(~isfinite(trough_idx)) || ...
            any(trough_idx ~= round(trough_idx)) || any(trough_idx < 1)
        bad = find(~isfinite(trough_idx) | trough_idx ~= round(trough_idx) | ...
            trough_idx < 1, 1);
        [ok, message, issue] = invalid(sprintf( ...
            'Trough sample %d must be a finite positive integer.', bad), ...
            'trough_idx', bad, peak_idx(bad), trough_idx(bad), ...
            peak_idx(bad + 1));
        return;
    end

    between_indices = peak_idx(1:end-1) < trough_idx & ...
        trough_idx < peak_idx(2:end);
    bad = find(~between_indices, 1);
    if ~isempty(bad)
        [ok, message, issue] = invalid(sprintf( ...
            ['Interval %d has trough sample %d; it must lie strictly ' ...
             'between peak samples %d and %d.'], ...
            bad, trough_idx(bad), peak_idx(bad), peak_idx(bad + 1)), ...
            'trough_idx', bad, peak_idx(bad), trough_idx(bad), ...
            peak_idx(bad + 1));
        return;
    end

    peak_t = field_column(b, 'peak_t');
    trough_t = field_column(b, 'trough_t');
    if ~isempty(peak_t) && numel(peak_t) ~= numel(peak_idx)
        [ok, message, issue] = invalid( ...
            'peak_t and peak_idx must have equal lengths.', ...
            'peak_t_count', NaN, NaN, NaN, NaN);
        return;
    end
    if ~isempty(trough_t) && numel(trough_t) ~= n_intervals
        [ok, message, issue] = invalid( ...
            'trough_t must contain one value per adjacent peak pair.', ...
            'trough_t_count', NaN, NaN, NaN, NaN);
        return;
    end
    if ~isempty(peak_t) && ~isempty(trough_t)
        finite_trough = isfinite(trough_t);
        between_times = peak_t(1:end-1) < trough_t & ...
            trough_t < peak_t(2:end);
        bad = find(finite_trough & ~between_times, 1);
        if ~isempty(bad)
            [ok, message, issue] = invalid(sprintf( ...
                ['Interval %d has trough time %.9g s; it must lie strictly ' ...
                 'between peak times %.9g s and %.9g s.'], ...
                bad, trough_t(bad), peak_t(bad), peak_t(bad + 1)), ...
                'trough_t', bad, peak_idx(bad), trough_idx(bad), ...
                peak_idx(bad + 1));
        end
    end
end

function values = field_column(s, name)
% FIELD_COLUMN Return a named field as a column, or empty when absent.

    values = [];
    if isfield(s, name)
        values = s.(name)(:);
    end
end

function issue = empty_issue()
% EMPTY_ISSUE Initialize machine-readable invalid-landmark details.

    issue = struct('field', '', 'interval_idx', NaN, ...
        'left_peak_idx', NaN, 'trough_idx', NaN, 'right_peak_idx', NaN);
end

function [ok, message, issue] = invalid( ...
    message, field, interval_idx, left_peak_idx, trough_idx, right_peak_idx)
% INVALID Construct one failed validation result.

    ok = false;
    issue = struct('field', field, 'interval_idx', interval_idx, ...
        'left_peak_idx', left_peak_idx, 'trough_idx', trough_idx, ...
        'right_peak_idx', right_peak_idx);
end
