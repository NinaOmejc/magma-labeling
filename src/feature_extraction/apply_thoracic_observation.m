function [cycles, changed] = apply_thoracic_observation(cycles, data, config)
% APPLY_THORACIC_OBSERVATION Exclude thoracic cycles while retaining their trace.
% Clearing the observation re-extracts only the thoracic belt; abdominal manual
% landmarks and the missing-belt policy are preserved.
    changed = false;
    if ~isfield(cycles, 'provenance'), cycles.provenance = struct(); end
    suppressed = isfield(cycles.provenance, 'thoracic_extraction_suppressed') && ...
        cycles.provenance.thoracic_extraction_suppressed;
    if minimal_thoracic_excursion(config)
        if ~suppressed || ~isempty(cycles.lungs.peak_idx)
            x = cycles.lungs.x0;
            cycles.lungs = empty_respiration_feature('lungs');
            cycles.lungs.x0 = x;
            changed = true;
        end
        cycles.provenance.thoracic_extraction_suppressed = true;
    elseif suppressed && ~is_lung_belt_ignored(config)
        resolved = resolve_signal_channels(config);
        idx = resolved.channels.lungs_idx;
        if ~isempty(idx) && ~is_valid_breath_signal(cycles.lungs, false)
            cycles.lungs = extract_respiration_feature(data(:, idx), config, 'lungs');
        end
        cycles.provenance.thoracic_extraction_suppressed = false;
        cycles.provenance.thoracic_landmarks_recomputed = true;
        changed = true;
    end
    if isfield(config, 'recording_observations')
        changed = changed || ~isfield(cycles, 'recording_observations') || ...
            cycles.recording_observations.revision ~= config.recording_observations.revision;
        cycles.recording_observations = config.recording_observations;
    end
end
