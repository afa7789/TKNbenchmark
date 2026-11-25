## linreg: ordinary least-squares regression read from standard input.
##
## Input:  "n k" followed by n rows of k features and the response y.
## Output: b0, b1, ..., bk and R^2, one per line.

1;

function vals = parse_values (text)
  ## Prefer the compiled parser built by build.sh; sscanf is the fallback.
  if (exist ("parse_numbers") == 3)
    vals = parse_numbers (text);
  else
    vals = sscanf (text, "%f");
  endif
endfunction

function [x, y] = read_problem (path)
  ## Reading through a named stream is far faster than the stdin handle.
  fid = fopen (path, "r");
  if (fid < 0)
    error ("linreg: cannot open %s", path);
  endif
  unwind_protect
    text = fread (fid, Inf, "*char")';
  unwind_protect_cleanup
    fclose (fid);
  end_unwind_protect
  vals = parse_values (text);
  if (numel (vals) < 2)
    error ("linreg: missing header");
  endif
  n = vals(1);
  k = vals(2);
  if (numel (vals) < 2 + n * (k + 1))
    error ("linreg: expected %d data values, got %d", n * (k + 1), numel (vals) - 2);
  endif
  data = reshape (vals(3:2 + n * (k + 1)), k + 1, n)';
  x = data(:, 1:k);
  y = data(:, k + 1);
endfunction

function [beta, r2] = ols_fit (x, y)
  ## Center the data so the intercept decouples; solve the slopes by QR.
  mx = mean (x, 1);
  my = mean (y);
  xc = x - mx;
  yc = y - my;
  slopes = xc \ yc;
  beta = [my - mx * slopes; slopes];
  resid = yc - xc * slopes;
  r2 = 1 - sumsq (resid) / sumsq (yc);
endfunction

addpath (fullfile (fileparts (mfilename ("fullpath")), "build"));
[x, y] = read_problem ("/dev/stdin");
[beta, r2] = ols_fit (x, y);
printf ("%.15g\n", [beta; r2]);
