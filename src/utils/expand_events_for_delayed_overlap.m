function ev = expand_events_for_delayed_overlap(ev, delay_sec)
% expand_events_for_delayed_overlap
% Move event starts earlier so an event ending after the source event can be
% associated as a delayed response without also matching events that ended
% before the source event.

    if isempty(ev) || delay_sec <= 0
        return;
    end

    for i = 1:numel(ev)
        ev(i).start_t = max(0, ev(i).start_t - delay_sec);
    end
end
