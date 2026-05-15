function ref = get_resp_ref_on_grid(baseline, belt, t_grid)

switch belt
    case 'lungs'
        static_ref = baseline.lungs_amp_ref;
        rolling_field = 'lungs_amp_ref';
    case 'diap'
        static_ref = baseline.diap_amp_ref;
        rolling_field = 'diap_amp_ref';
    otherwise
        error('Unknown belt: %s', belt);
end

if isfield(baseline, 'rolling') && ...
        isfield(baseline.rolling, 't_grid') && ...
        isfield(baseline.rolling, rolling_field)

    ref = interp1( ...
        baseline.rolling.t_grid, ...
        baseline.rolling.(rolling_field), ...
        t_grid, ...
        'previous', ...
        'extrap');

    bad = ~isfinite(ref) | ref <= 0;
    ref(bad) = static_ref;
else
    ref = static_ref * ones(size(t_grid));
end

end
