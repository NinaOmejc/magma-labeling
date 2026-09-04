function values = read_hdf5_text(filename, dataset)
% READ_HDF5_TEXT Read hdf5 text.
%
% Syntax:
%   values = read_hdf5_text(filename, dataset)
%
% Inputs:
%   filename - File or dataset path.
%   dataset - File or dataset path.
%
% Outputs:
%   values - Computed numeric value.

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
