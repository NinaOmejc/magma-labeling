function tf = minimal_thoracic_excursion(config)
% MINIMAL_THORACIC_EXCURSION Read the observation used by this analysis.
% This never changes missing-sensor configuration or the recorded signal.
    tf = false;
    if isfield(config, 'recording_observations') && ~isempty(config.recording_observations)
        observation = config.recording_observations;
        if observation.subject ~= config.subject || observation.measurement ~= config.measure
            error('MAGMA:Observation:IdentityMismatch', 'Observation does not match subject and measurement.');
        end
        tf = strcmp(observation.status, 'observed') && ~is_lung_belt_ignored(config);
    end
end
