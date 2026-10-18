function bundle = attach_thoracic_excursion_phenotype(bundle,context)
% ATTACH_THORACIC_EXCURSION_PHENOTYPE Update only features 23-24, not the first 22.
% This does not touch historical review snapshots or recalculate signal QC.
    layers = {'automatic','reviewed'};
    for i = 1:2
        layer_context = context;
        if i == 1
            layer_context.recording_observations = [];
            if isfield(context,'analysis_recording_observations')
                layer_context.recording_observations = context.analysis_recording_observations;
            end
        end
        group = build_thoracic_excursion_phenotype(layer_context);
        layer = bundle.(layers{i});
        layer.recording_level.minimal_thoracic_excursion = group;
        summary = align_phenotype_numeric_summary(layer.numeric_summary);
        summary.values(23:24) = group.values;
        summary.available(23:24) = group.available;
        summary.coverage_fraction(23:24) = group.coverage_fraction;
        summary.missing_reason(23:24) = group.missing_reason;
        validate_compact_phenotype_features(summary);
        layer.numeric_summary = summary;
        layer.version = 'magma_phenotypes_v8';
        bundle.(layers{i}) = layer;
    end
    bundle.version = 'magma_phenotype_bundle_v8';
end
