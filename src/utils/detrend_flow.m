% subtract the trend and the average value from the time series
%
% The trend is calculated using a moving average with a window length
% of window_l seconds.
%
% (t_series, 10, 200)


function [output,trend,trend1] = detrend_flow(t_series, sampl_freq, window_l)

[idim jdim] = size(t_series);		%The next three lines check that data is correct way round

if idim > 1 
    t_series = t_series';
end

window_s = round(window_l*sampl_freq); % the length of the window in samples % it has to be an odd number !!!

if mod(window_s,2) == 0
   window_s = window_s + 1;
end

dim = length(t_series);

trend = zeros(dim,1);

for i = 1 : dim-window_s+1  % the number of the samples calculated
    trend( i + (window_s-1)/2 ) = mean(t_series(i:i+window_s-1));
end
	
% The first samples of the trend have the same value as the first calculated sample of the trend
% Their number is equal to one half of the samples in the window
%
% The last samples of the trend have a value equal to the last calculated sample of the trend 
% Their number is equal to one half of the samples in the window

first_value = trend( 1+(window_s-1)/2 );
last_value = trend( dim - (window_s-1)/2 );


for stevec = 1 : (window_s-1)/2
     trend(stevec) = first_value;
end

for stevec = dim-(window_s-1)/2+1 : dim
     trend(stevec) = last_value;
end
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
[dimx dimy]=size(trend);

if dimx>dimy
    trend = trend';
end

vmesni = t_series-trend;
trend1 = trend;
trend = trend + mean(vmesni);

% the average value of the signal is subtracted from the original signal
output = t_series - trend;

[dimx dimy]=size(output);

if dimx>dimy
    output = output';
end

%time = linspace(0, (dim-1) * 1/sampl_freq, dim );
%plot(time,output)