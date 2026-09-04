
function ev = expand_events_time(ev, pad_sec, t_max)
% EXPAND_EVENTS_TIME Pad event boundaries within a recording duration.
%
% Syntax:
%   ev = expand_events_time(ev, pad_sec, t_max)
%
% Inputs:
%   ev - Event structure data.
%   pad_sec - Padding applied to each boundary in seconds.
%   t_max - Maximum recording time in seconds.
%
% Outputs:
%   ev - Event structure array.

    for i = 1:numel(ev)
        ev(i).start_t = max(0, ev(i).start_t - pad_sec);
        ev(i).end_t   = min(t_max, ev(i).end_t + pad_sec);
    end
end
