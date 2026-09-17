function method = resolve_respiration_amplitude_method(config)
% RESOLVE_RESPIRATION_AMPLITUDE_METHOD Validate the selected breath excursion.
% Missing/empty settings use the backwards-compatible expiratory definition.

    method = 'expiratory';
    if isfield(config, 'resp') && isstruct(config.resp) && ...
            isfield(config.resp, 'amp_method') && ...
            ~isempty(config.resp.amp_method)
        configured = string(config.resp.amp_method);
        if ~isscalar(configured)
            error('MAGMA:Respiration:InvalidAmplitudeMethod', ...
                'config.resp.amp_method must be expiratory, inspiratory, or symmetric.');
        end
        method = lower(strtrim(char(configured)));
    end

    if ~ismember(method, {'expiratory', 'inspiratory', 'symmetric'})
        error('MAGMA:Respiration:InvalidAmplitudeMethod', ...
            ['Unknown config.resp.amp_method ''%s''. Allowed values are ' ...
             '''expiratory'', ''inspiratory'', and ''symmetric''.'], method);
    end
end
