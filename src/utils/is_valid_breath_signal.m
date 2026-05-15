function tf = is_valid_breath_signal(breaths, require_amp)
% True when a breaths struct is usable for detection logic.

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
