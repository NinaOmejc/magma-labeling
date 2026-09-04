% Time-localized wavelet phase-coherence implementation by Dmytro Iatsenko.

function TPC = tlphcoh(TFR1,TFR2,freq,fs,varargin)
% TLPHCOH Compute time-localized wavelet phase coherence.
%
% Syntax:
%   TPC = tlphcoh(TFR1, TFR2, freq, fs, varargin)
%
% Inputs:
%   TFR1 - Wavelet transform of the first signal.
%   TFR2 - Wavelet transform of the second signal.
%   freq - Wavelet frequencies in hertz.
%   fs - Sampling frequency in hertz.
%   varargin - Optional number of cycles used for the adaptive window.
%
% Outputs:
%   TPC - Time-localized phase coherence.

[NF,L]=size(TFR1);
if nargin>4, wsize=varargin{1}; else wsize=10; end

IPC=exp(1i*angle(TFR1.*conj(TFR2)));
ZPC=IPC; ZPC(isnan(ZPC))=0; cumPC=[zeros(NF,1),cumsum(ZPC,2)];
TPC=zeros(NF,L)*NaN;
for fn=1:NF
    cs=IPC(fn,:); cumcs=cumPC(fn,:);
    tn1=find(~isnan(cs),1,'first'); tn2=find(~isnan(cs),1,'last');
    
    window=round((wsize/freq(fn))*fs); window=window+1-mod(window,2); hw=floor(window/2);
    
    if ~isempty(tn1+tn2) && window<=tn2-tn1
    locpc=abs(cumcs(tn1+window:tn2+1)-cumcs(tn1:tn2-window+1))/window;
    TPC(fn,tn1+hw:tn2-hw)=locpc;
    end
end

end
