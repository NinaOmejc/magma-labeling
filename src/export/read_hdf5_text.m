function values = read_hdf5_text(filename, dataset)
% READ_HDF5_TEXT Decode a UTF-8 string array written by the MAGMA HDF5 exporter.
%
% Inputs:
%   filename - HDF5 file path.
%   dataset  - Dataset path containing zero-padded UTF-8 byte columns.
%
% Outputs:
%   values - 1 x N cell array of character vectors, or an empty cell column
%            when the dataset carries the is_empty attribute.

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
