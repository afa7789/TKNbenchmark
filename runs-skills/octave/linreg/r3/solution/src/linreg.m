1;

## Read all of standard input and return the numeric tokens as a column.
## Reading through a fresh descriptor on /dev/stdin is far faster than the
## built-in stdin stream for large inputs; fall back to stdin if unavailable.
function v = read_numbers ()
  fid = fopen ("/dev/stdin", "r");
  if (fid < 0)
    fid = stdin;
  endif
  unwind_protect
    txt = fread (fid, Inf, "uint8=>char")';
  unwind_protect_cleanup
    if (fid != stdin)
      fclose (fid);
    endif
  end_unwind_protect
  v = sscanf (txt, "%f");
endfunction

## Ordinary least squares with intercept.  Features are centred before the
## QR-based solve, which keeps the problem well conditioned when the features
## have large offsets.  Returns [b0; b1; ...; bk] and R^2.
function [beta, r2] = ols_fit (x, y)
  xm = mean (x, 1);
  ym = mean (y);
  xc = x - xm;
  yc = y - ym;
  b = xc \ yc;
  beta = [ym - xm * b; b];
  res = yc - xc * b;
  r2 = 1 - sumsq (res) / sumsq (yc);
endfunction

function main ()
  v = read_numbers ();
  if (numel (v) < 2)
    error ("linreg: missing header line");
  endif
  n = v(1);
  k = v(2);
  need = n * (k + 1);
  if (numel (v) - 2 < need)
    error ("linreg: expected %d values, got %d", need, numel (v) - 2);
  endif
  data = reshape (v(3:need + 2), k + 1, n)';
  [beta, r2] = ols_fit (data(:, 1:k), data(:, k + 1));
  fprintf ("%.15g\n", [beta; r2]);
endfunction

main ();
