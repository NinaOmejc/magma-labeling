function tf = is_lung_belt_ignored(config)
% is_lung_belt_ignored  True when the configured lung/thorax belt is marked broken.

    tf = false;

    if ~isfield(config, 'problems') || ...
            ~isfield(config.problems, 'subjects_with_broken_lung_belt') || ...
            ~isfield(config, 'subject')
        return;
    end

    if ~any(config.subject == config.problems.subjects_with_broken_lung_belt)
        return;
    end

    if isfield(config, 'channels') && isfield(config.channels, 'lungs_source')
        tf = strcmp(config.channels.lungs_source, 'lungs');
    else
        tf = true;
    end
end
