function candidates = events_to_candidate_events( ...
    events, belt, accepted, rejection_reason, uncertainty_sec)
% EVENTS_TO_CANDIDATE_EVENTS Convert event-like intervals to compact candidates.
% Scalar metadata is expanded across events. rejection_reason uses the stable
% vocabulary '', 'too_short', 'no_support', or 'unevaluable'.

    candidates = empty_candidate_events();
    if isempty(events)
        return;
    end
    allowed_belts = {'', 'lungs', 'diaph', 'both', 'combined'};
    allowed_reasons = {'', 'too_short', 'no_support', 'unevaluable'};
    for i = 1:numel(events)
        candidate_belt = char(string(value_at(belt, i)));
        candidate_accepted = logical(value_at(accepted, i));
        candidate_reason = char(string(value_at(rejection_reason, i)));
        candidate_uncertainty = double(value_at(uncertainty_sec, i));
        if ~ismember(candidate_belt, allowed_belts)
            error('MAGMA:CandidateEvents:InvalidBelt', ...
                'Candidate belt must be lungs, diaph, both, combined, or empty.');
        end
        if ~ismember(candidate_reason, allowed_reasons)
            error('MAGMA:CandidateEvents:InvalidRejectionReason', ...
                'Unsupported candidate rejection reason: %s.', candidate_reason);
        end
        if candidate_accepted && ~isempty(candidate_reason)
            error('MAGMA:CandidateEvents:AcceptedWithReason', ...
                'Accepted candidates must have an empty rejection reason.');
        end
        if ~isfinite(candidate_uncertainty) || candidate_uncertainty < 0
            error('MAGMA:CandidateEvents:InvalidUncertainty', ...
                'Candidate uncertainty must be finite and nonnegative.');
        end
        required = {'start_idx', 'end_idx', 'start_t', 'end_t', 'duration'};
        if ~all(isfield(events(i), required))
            error('MAGMA:CandidateEvents:InvalidEvent', ...
                'Candidate source events must contain canonical coordinates.');
        end
        candidates(end + 1, 1) = struct( ...
            'start_idx', events(i).start_idx, ...
            'end_idx', events(i).end_idx, ...
            'start_t', events(i).start_t, ...
            'end_t', events(i).end_t, ...
            'duration', events(i).duration, ...
            'belt', candidate_belt, ...
            'accepted', candidate_accepted, ...
            'rejection_reason', candidate_reason, ...
            'uncertainty_sec', candidate_uncertainty); %#ok<AGROW>
    end
end

function value = value_at(values, index)
% VALUE_AT Expand scalar metadata or select one aligned array/cell element.

    if ischar(values) || (isstring(values) && isscalar(values)) || ...
            isscalar(values)
        value = values;
    elseif iscell(values)
        value = values{index};
    else
        value = values(index);
    end
end
