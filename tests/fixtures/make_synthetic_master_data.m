function data = make_synthetic_master_data(n_samples, fs)
% make_synthetic_master_data  Deterministic six-channel master-rate input.

    t = (0:n_samples-1)' / fs;
    data = zeros(n_samples, 6);
    data(:, 1) = sin(2*pi*1.1*t) + 0.05*cos(2*pi*3.7*t);
    data(:, 2) = cos(2*pi*0.9*t) - 0.03*sin(2*pi*4.1*t);
    data(:, 3) = 96 - 0.2*sin(2*pi*0.02*t);
    data(:, 4) = 0.012*t + sin(2*pi*0.25*t);
    data(:, 5) = 80 + 4*sin(2*pi*1.0*t);
    data(:, 6) = -0.009*t + 0.8*sin(2*pi*0.25*t + 0.15);
end
