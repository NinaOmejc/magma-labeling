function values = read_hdf5_text(filename, dataset)
% read_hdf5_text  Decode text written by export_results_hdf5.
    encoded = h5read(filename, dataset);
    info = h5info(filename, dataset);
    if any(strcmp({info.Attributes.Name}, 'is_empty'))
        values = cell(0, 1);
        return;
    end
    values = cell(1, size(encoded, 2));
    for i = 1:size(encoded, 2)
        bytes = encoded(:, i);
        bytes = bytes(bytes ~= 0);
        values{i} = native2unicode(bytes(:)', 'UTF-8');
    end
end
