function group = build_thoracic_excursion_phenotype(context)
% BUILD_THORACIC_EXCURSION_PHENOTYPE Independent recording-scope readouts.
% Categorical status remains authoritative in recording_observations.
    if nargin < 1, context = struct(); end
    group = struct('name','Minimal or absent thoracic excursion', ...
        'version','minimal_thoracic_excursion_phenotype_v1', ...
        'feature_names',{{'thoracic_respiratory_rhythmicity','minimal_thoracic_excursion_clinician'}}, ...
        'scope','recording','values',[NaN NaN],'available',[false false], ...
        'coverage_fraction',[NaN NaN], ...
        'missing_reason',{{'not_computed','not_assessed'}}, ...
        'signal_provenance',struct(),'clinician_provenance',struct(), ...
        'interpretation',['Rhythmicity is respiratory-frequency spectral concentration, ' ...
        'not calibrated excursion, tidal volume, or a probability. No binary threshold.']);
    if isfield(context,'respiratory_signal_qc') && isfield(context.respiratory_signal_qc,'thoracic')
        qc = context.respiratory_signal_qc.thoracic;
        group.signal_provenance = qc;
        group.missing_reason{1} = qc.missing_reason;
        group.coverage_fraction(1) = qc.valid_coverage_fraction;
        if qc.available && isfinite(qc.thoracic_respiratory_rhythmicity)
            group.values(1) = qc.thoracic_respiratory_rhythmicity;
            group.available(1) = true; group.missing_reason{1} = '';
        end
    end
    if isfield(context,'recording_observations') && ~isempty(context.recording_observations)
        obs = context.recording_observations;
        fields = {'revision','timestamp','reviewer_role','annotation_source','scope'};
        for i = 1:numel(fields)
            if isfield(obs,fields{i}), group.clinician_provenance.(fields{i}) = obs.(fields{i}); end
        end
        if ismember(obs.status,{'observed','not_observed'})
            group.values(2) = double(strcmp(obs.status,'observed'));
            group.available(2) = true; group.coverage_fraction(2) = 1;
            group.missing_reason{2} = '';
        end
    end
end
