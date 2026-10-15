function k = makeKey(a,b)
    k = lower(strtrim(string(a))) + "|" + ...
        lower(strtrim(string(b)));
end