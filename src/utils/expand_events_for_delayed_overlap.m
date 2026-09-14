function ev = expand_events_for_delayed_overlap(ev, delay_sec)
% EXPAND_EVENTS_FOR_DELAYED_OVERLAP Extend event starts to capture delayed responses.
%
% Inputs:
%   ev        - Event struct array with start_t boundaries in seconds.
%   delay_sec - Seconds to subtract from each start, clipped at recording time zero.
%
% Outputs:
%   ev - Event structure array.

    if isempty(ev) || delay_sec <= 0
        return;
    end

    for i = 1:numel(ev)
        ev(i).start_t = max(0, ev(i).start_t - delay_sec);
    end
end
