function tf = is_lung_belt_ignored(config)
% IS_LUNG_BELT_IGNORED Apply recording-specific known-lung-belt exclusions.
% config.problems.missing_lung_belt is N-by-2 [subject,measurement]. Generic
% respiratory channels are not discarded merely because they fill the lung role.

    tf = false;

    if ~isfield(config, 'problems') || ...
            ~isfield(config.problems, 'missing_lung_belt') || ...
            ~isfield(config, 'subject') || ~isfield(config, 'measure')
        return;
    end

    missing_lung_belt = config.problems.missing_lung_belt;
    if isempty(missing_lung_belt)
        return;
    end
    if ~isnumeric(missing_lung_belt) || size(missing_lung_belt, 2) ~= 2
        error('MAGMA:Config:InvalidMissingLungBelt', ...
            'config.problems.missing_lung_belt must be an N-by-2 numeric matrix of [subject, measurement] pairs.');
    end

    recording_is_excluded = any( ...
        missing_lung_belt(:, 1) == config.subject & ...
        missing_lung_belt(:, 2) == config.measure);
    if ~recording_is_excluded
        return;
    end

    if isfield(config, 'channels') && isfield(config.channels, 'lungs_source')
        tf = strcmp(config.channels.lungs_source, 'lungs');
    else
        tf = true;
    end
end
