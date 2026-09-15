function result = estimate_matrix_pencil_modulation(envelope, fs)
% ESTIMATE_MATRIX_PENCIL_MODULATION Fit DC plus one conjugate sinusoidal pair.
% The SVD-based order-three Matrix Pencil model follows Guyot et al. 2020.
% Complex amplitudes are stored as real/imaginary components so diagnostics
% remain directly serializable by the MAGMA HDF5 exporter.

    model_order = 3;
    result = empty_result(model_order);
    if ~isnumeric(envelope) || ~isvector(envelope) || ...
            ~isscalar(fs) || ~isfinite(fs) || fs <= 0
        result.failure_reason = 'invalid_input';
        return;
    end

    x = double(envelope(:));
    n_samples = numel(x);
    result.n_samples = n_samples;
    if n_samples < 12
        result.failure_reason = 'too_short';
        return;
    end
    if any(~isfinite(x))
        result.failure_reason = 'nonfinite_input';
        return;
    end
    signal_scale = max([1; abs(x)]);
    if std(x, 0) <= 1e-8 * signal_scale
        result.failure_reason = 'no_identifiable_modulation';
        return;
    end

    pencil_rows = floor(n_samples / 2);
    pencil_columns = n_samples - pencil_rows;
    if min(pencil_rows, pencil_columns) < model_order
        result.failure_reason = 'too_short';
        return;
    end
    y0 = zeros(pencil_rows, pencil_columns);
    y1 = zeros(pencil_rows, pencil_columns);
    for column = 1:pencil_columns
        y0(:, column) = x(column:column + pencil_rows - 1);
        y1(:, column) = x(column + 1:column + pencil_rows);
    end

    try
        [u, s, v] = svd(y0, 'econ');
        singular_values = diag(s);
        result.singular_values = singular_values;
        if numel(singular_values) < model_order || singular_values(1) <= 0
            result.failure_reason = 'insufficient_rank';
            return;
        end
        rank_tolerance = max(size(y0)) * eps(singular_values(1));
        if singular_values(model_order) <= rank_tolerance
            result.failure_reason = 'insufficient_rank';
            return;
        end
        ur = u(:, 1:model_order);
        sr = s(1:model_order, 1:model_order);
        vr = v(:, 1:model_order);
        reduced_pencil = sr \ (ur' * y1 * vr);
        poles = eig(reduced_pencil);
    catch
        result.failure_reason = 'decomposition_failed';
        return;
    end
    if numel(poles) ~= model_order || any(~isfinite(poles)) || ...
            any(abs(poles) <= eps)
        result.failure_reason = 'invalid_poles';
        return;
    end

    frequencies = angle(poles) * fs / (2 * pi);
    [~, dc_index] = min(abs(frequencies));
    frequency_resolution = fs / n_samples;
    if abs(frequencies(dc_index)) > max(frequency_resolution, 1e-6)
        result.failure_reason = 'no_dc_component';
        return;
    end

    positive = setdiff(find(frequencies > 1e-8), dc_index);
    negative = setdiff(find(frequencies < -1e-8), dc_index);
    [positive_index, negative_index, pair_error_hz] = ...
        closest_frequency_pair(frequencies, positive, negative);
    if isempty(positive_index) || ...
            pair_error_hz > max(2 * frequency_resolution, 0.002)
        result.failure_reason = 'no_conjugate_modulation_pair';
        return;
    end
    pole_pair_error = abs(poles(positive_index) - ...
        conj(poles(negative_index))) / max(abs(poles(positive_index)), eps);
    if ~isfinite(pole_pair_error) || pole_pair_error > 0.25
        result.failure_reason = 'no_conjugate_modulation_pair';
        return;
    end

    vandermonde = zeros(n_samples, model_order);
    sample_index = (0:n_samples - 1)';
    for component = 1:model_order
        vandermonde(:, component) = poles(component) .^ sample_index;
    end
    try
        amplitudes = vandermonde \ x;
    catch
        result.failure_reason = 'amplitude_fit_failed';
        return;
    end
    if any(~isfinite(amplitudes))
        result.failure_reason = 'amplitude_fit_failed';
        return;
    end

    dc_amplitude = real(amplitudes(dc_index));
    modulation_amplitude = amplitudes(positive_index);
    fm_hz = frequencies(positive_index);
    h = 2 * abs(modulation_amplitude) / dc_amplitude;
    reconstructed = real(vandermonde * amplitudes);
    reconstruction_error = norm(x - reconstructed) / max(norm(x), eps);
    if ~isfinite(dc_amplitude) || dc_amplitude <= 0 || ...
            ~isfinite(fm_hz) || fm_hz <= 0 || ~isfinite(h)
        result.failure_reason = 'invalid_model_parameters';
        return;
    end

    result.evaluable = true;
    result.failure_reason = '';
    result.rank_used = model_order;
    result.dc_amplitude = dc_amplitude;
    result.modulation_amplitude_real = real(modulation_amplitude);
    result.modulation_amplitude_imag = imag(modulation_amplitude);
    result.modulation_amplitude_magnitude = abs(modulation_amplitude);
    result.fm_hz = fm_hz;
    result.h = h;
    result.reconstruction_error = reconstruction_error;
    result.conjugate_pair_error = pole_pair_error;
end

function [positive_index, negative_index, error_hz] = ...
    closest_frequency_pair(frequencies, positive, negative)
% CLOSEST_FREQUENCY_PAIR Find the most nearly conjugate signed frequencies.

    positive_index = [];
    negative_index = [];
    error_hz = Inf;
    for i = 1:numel(positive)
        for j = 1:numel(negative)
            candidate_error = abs(frequencies(positive(i)) + ...
                frequencies(negative(j)));
            if candidate_error < error_hz
                positive_index = positive(i);
                negative_index = negative(j);
                error_hz = candidate_error;
            end
        end
    end
end

function result = empty_result(model_order)
% EMPTY_RESULT Return stable serializable Matrix Pencil diagnostics.

    result = struct( ...
        'evaluable', false, ...
        'failure_reason', 'not_evaluated', ...
        'model_order', model_order, ...
        'n_samples', 0, ...
        'rank_used', 0, ...
        'dc_amplitude', NaN, ...
        'modulation_amplitude_real', NaN, ...
        'modulation_amplitude_imag', NaN, ...
        'modulation_amplitude_magnitude', NaN, ...
        'fm_hz', NaN, ...
        'h', NaN, ...
        'reconstruction_error', NaN, ...
        'conjugate_pair_error', NaN, ...
        'singular_values', []);
end
