function linreg ()
  % LINREG  Ordinary least-squares regression reading from stdin.
  %   Input:  "n k" header, then n rows of k features followed by the response.
  %   Output: intercept, k slopes, and R^2, one per line.

  vals = sscanf (read_stdin (), "%f");

  if (numel (vals) < 2)
    error ("linreg: missing header");
  endif
  n = vals(1);
  k = vals(2);
  cols = k + 1;
  if (numel (vals) < 2 + n * cols)
    error ("linreg: expected %d data values, got %d", n * cols, numel (vals) - 2);
  endif

  data = reshape (vals(3:2 + n * cols), cols, n)';
  clear vals;
  X = data(:, 1:k);
  y = data(:, cols);
  clear data;

  % Centre the features and response: this solves for the slopes on a
  % better-conditioned problem and yields the intercept from the means.
  mx = mean (X, 1);
  my = mean (y);
  Xc = X - mx;
  yc = y - my;
  clear X;

  b = Xc \ yc;                % QR-based least squares
  b0 = my - mx * b;

  resid = yc - Xc * b;
  ss_res = resid' * resid;
  ss_tot = yc' * yc;
  r2 = 1 - ss_res / ss_tot;

  printf ("%.15g\n", [b0; b; r2]);
endfunction

function text = read_stdin ()
  % Read all of standard input as one row of chars.  Opening /dev/stdin
  % directly is far faster than fread on Octave's stdin stream.
  [fid, msg] = fopen ("/dev/stdin", "r");
  if (fid < 0)
    warning ("linreg: cannot open /dev/stdin (%s); using stdin stream", msg);
    fid = stdin;
  endif
  text = fread (fid, [1, Inf], "*char");
  if (fid != stdin)
    fclose (fid);
  endif
endfunction
