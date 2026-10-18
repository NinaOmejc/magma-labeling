function [cycles, changed] = apply_thoracic_observation(cycles, ~, config)
% APPLY_THORACIC_OBSERVATION Gate thoracic evidence while retaining landmarks.
% The observation gates downstream evidence, never deletes or regenerates saved
% landmarks. Clearing it makes existing landmarks eligible again.
    if ~isfield(cycles, 'provenance'), cycles.provenance = struct(); end
    suppressed = isfield(cycles.provenance, 'thoracic_extraction_suppressed') && ...
        cycles.provenance.thoracic_extraction_suppressed;
    excluded = minimal_thoracic_excursion(config);
    changed = suppressed ~= excluded;
    cycles.provenance.thoracic_extraction_suppressed = excluded;
    if isfield(config, 'recording_observations')
        changed = changed || ~isfield(cycles, 'recording_observations') || ...
            cycles.recording_observations.revision ~= config.recording_observations.revision;
        cycles.recording_observations = config.recording_observations;
    end
end
