function linreg ()
  % LINREG  Ordinary least-squares regression reading from stdin.
  %   Input:  "n k" header, then n rows of k features followed by y.
  %   Output: b0..bk, then R^2, one per line.

  raw = fileread ("/dev/stdin");
  vals = sscanf (raw, "%f");
  clear raw;

  if (numel (vals) < 2)
    error ("linreg: missing header");
  endif
  n = vals(1);
  k = vals(2);
  ncol = k + 1;
  if (numel (vals) < 2 + n * ncol)
    error ("linreg: expected %d values, got %d", n * ncol, numel (vals) - 2);
  endif

  data = reshape (vals(3:2 + n * ncol), ncol, n)';
  clear vals;
  X = data(:, 1:k);
  y = data(:, ncol);
  clear data;

  % Center to improve conditioning; the intercept is recovered afterwards.
  mx = mean (X, 1);
  my = mean (y);
  Xc = X - mx;
  yc = y - my;
  clear X y;

  beta = Xc \ yc;
  b0 = my - mx * beta;

  res = yc - Xc * beta;
  ss_res = res' * res;
  ss_tot = yc' * yc;
  r2 = 1 - ss_res / ss_tot;

  printf ("%.15g\n", [b0; beta; r2]);
endfunction
