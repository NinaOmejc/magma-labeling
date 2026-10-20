function panels = respiratory_asynchrony_plot_panels(config)
% RESPIRATORY_ASYNCHRONY_PLOT_PANELS Return ordered diagnostic panel keys.

    panels = {'belts', 'phase_offset', 'phase_consistency'};
    settings = resolve_respiratory_asynchrony_settings(config);
    show_legacy = logical(settings.plot_legacy_coherence);
    if show_legacy
        panels{end + 1} = 'legacy_coherence';
    end
end
