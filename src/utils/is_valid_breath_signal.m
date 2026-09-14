function tf = is_valid_breath_signal(breaths, require_amp)
% IS_VALID_BREATH_SIGNAL Check whether a belt supports timing or amplitude analysis.
% breaths must not be marked ok=false and needs at least two finite peak_t values
% in seconds. With require_amp=true, at least two positive finite amplitudes are
% also required. tf is a scalar logical.

    if nargin < 2
        require_amp = false;
    end

    tf = false;
    if isempty(breaths) || ~isstruct(breaths)
        return;
    end

    if isfield(breaths, 'ok') && ~breaths.ok
        return;
    end

    if ~isfield(breaths, 'peak_t') || isempty(breaths.peak_t)
        return;
    end

    peak_t = breaths.peak_t(:);
    peak_t = peak_t(isfinite(peak_t));
    if numel(peak_t) < 2
        return;
    end

    if require_amp
        if ~isfield(breaths, 'amp') || isempty(breaths.amp)
            return;
        end
        amp = breaths.amp(:);
        amp = amp(isfinite(amp) & amp > 0);
        if numel(amp) < 2
            return;
        end
    end

    tf = true;
end
