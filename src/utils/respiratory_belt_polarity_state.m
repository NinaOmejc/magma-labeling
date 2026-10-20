function [checked, thoracic_flipped, diaphragm_flipped] = respiratory_belt_polarity_state(config)
% RESPIRATORY_BELT_POLARITY_STATE Read per-belt relative correction provenance.
% Older QC structs used .flipped for a diaphragm-only correction.

    checked = false;
    thoracic_flipped = false;
    diaphragm_flipped = false;
    if ~isfield(config, 'preprocessing') || ...
            ~isstruct(config.preprocessing) || ...
            ~isfield(config.preprocessing, 'belt_polarity_qc') || ...
            ~isstruct(config.preprocessing.belt_polarity_qc)
        return;
    end
    qc = config.preprocessing.belt_polarity_qc;
    if isfield(qc, 'checked') && isscalar(qc.checked)
        checked = logical(qc.checked);
    end
    if isfield(qc, 'thoracic_polarity_flipped') && ...
            isscalar(qc.thoracic_polarity_flipped)
        thoracic_flipped = logical(qc.thoracic_polarity_flipped);
    end
    if isfield(qc, 'diaphragm_polarity_flipped') && ...
            isscalar(qc.diaphragm_polarity_flipped)
        diaphragm_flipped = logical(qc.diaphragm_polarity_flipped);
    elseif isfield(qc, 'flipped') && isscalar(qc.flipped)
        diaphragm_flipped = logical(qc.flipped);
    end
end
