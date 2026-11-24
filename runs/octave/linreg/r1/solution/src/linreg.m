function linreg ()
  ## LINREG  Ordinary least-squares regression filter (stdin -> stdout).
  ##
  ## Input:  "n k" header, then n rows of k features followed by the response.
  ## Output: intercept, k slope coefficients, and R^2, one per line.

  raw = fread (stdin, Inf, "*char")';
  vals = sscanf (raw, "%f");
  clear raw;

  if (numel (vals) < 2)
    error ("linreg: missing header");
  endif
  n = vals(1);
  k = vals(2);
  need = n * (k + 1);
  if (numel (vals) - 2 < need)
    error ("linreg: expected %d data values, got %d", need, numel (vals) - 2);
  endif

  data = reshape (vals(3:2 + need), k + 1, n)';
  clear vals;
  X = data(:, 1:k);
  y = data(:, k + 1);
  clear data;

  ## Centre features and response for numerical stability; the intercept is
  ## recovered from the means.  Backslash uses a QR-based least-squares solve.
  mx = mean (X, 1);
  my = mean (y);
  Xc = X - mx;
  yc = y - my;
  clear X y;

  b = Xc \ yc;
  b0 = my - mx * b;

  res = yc - Xc * b;
  ss_res = res' * res;
  ss_tot = yc' * yc;
  r2 = 1 - ss_res / ss_tot;

  printf ("%.15g\n", [b0; b; r2]);
endfunction
