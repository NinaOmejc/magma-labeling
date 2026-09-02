function [value, available, reference_quality] = get_resp_session_reference(resp_ref, belt_name)
% get_resp_session_reference  Return one belt's fixed protocol/session reference.
% A categorical warning does not invalidate an available reference; the
% default action is to retain the data without drift or step correction.

    value = NaN;
    available = false;
    reference_quality = 'belt_unavailable';

    if ~isstruct(resp_ref) || ~isfield(resp_ref, belt_name) || ...
            ~isstruct(resp_ref.(belt_name))
        return;
    end

    belt = resp_ref.(belt_name);
    if isfield(belt, 'reference_quality')
        reference_quality = char(string(belt.reference_quality));
    end
    if ~isfield(belt, 'session') || ~isstruct(belt.session) || ...
            ~isfield(belt.session, 'available') || ~belt.session.available || ...
            ~isfield(belt.session, 'value')
        return;
    end

    value = belt.session.value;
    available = isscalar(value) && isfinite(value) && value > 0;
    if ~available
        value = NaN;
    end
end
