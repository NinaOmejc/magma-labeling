function ev = expand_events_for_delayed_overlap(ev, delay_sec)
% EXPAND_EVENTS_FOR_DELAYED_OVERLAP Expand events for delayed overlap.
%
% Syntax:
%   ev = expand_events_for_delayed_overlap(ev, delay_sec)
%
% Inputs:
%   ev - Event structure data.
%   delay_sec - Duration or window length in seconds.
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
