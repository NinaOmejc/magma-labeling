function [amplitudes, failure_reason] = fit_matrix_pencil_amplitudes( ...
    vandermonde, envelope, model_order)
% FIT_MATRIX_PENCIL_AMPLITUDES Solve a numerically valid amplitude fit.

    amplitudes = [];
    failure_reason = '';
    try
        singular_values = svd(vandermonde, 'econ');
        if numel(singular_values) < model_order || singular_values(1) <= 0
            failure_reason = 'rank_deficient_amplitude_fit';
            return;
        end
        rank_tolerance = max(size(vandermonde)) * eps(singular_values(1));
        if singular_values(model_order) <= rank_tolerance
            failure_reason = 'rank_deficient_amplitude_fit';
            return;
        end
        amplitudes = vandermonde \ envelope;
    catch
        failure_reason = 'amplitude_fit_failed';
        return;
    end
    if any(~isfinite(amplitudes))
        amplitudes = [];
        failure_reason = 'amplitude_fit_failed';
    end
end
