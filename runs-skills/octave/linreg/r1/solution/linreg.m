## linreg: ordinary least-squares regression read from standard input.
##
## Input:  "n k" followed by n rows of k feature values and the response y.
## Output: b0, b1, ..., bk and R^2, one per line.

1;

function text = read_stdin ()
  ## fread on the built-in stdin stream is very slow for large inputs;
  ## reopening the descriptor through /dev/stdin is buffered and fast.
  fid = fopen ("/dev/stdin", "r");
  if (fid < 0)
    text = fread (stdin, Inf, "*char")';
    return;
  endif
  unwind_protect
    text = fread (fid, Inf, "*char")';
  unwind_protect_cleanup
    fclose (fid);
  end_unwind_protect
endfunction

function [n, k, data] = parse_input (text)
  vals = sscanf (text, "%f");
  if (numel (vals) < 2)
    error ("linreg: missing header line");
  endif
  n = vals(1);
  k = vals(2);
  need = n * (k + 1);
  if (numel (vals) - 2 < need)
    error ("linreg: expected %d values, got %d", need, numel (vals) - 2);
  endif
  data = reshape (vals(3:need + 2), k + 1, n)';
endfunction

function [beta, r2] = ols_fit (x, y)
  ## Centre the data so the intercept decouples and the QR-based solve
  ## is well conditioned even with large feature offsets.
  mx = mean (x, 1);
  my = mean (y);
  xc = x - mx;
  yc = y - my;
  b = xc \ yc;
  beta = [my - mx * b; b];
  res = yc - xc * b;
  r2 = 1 - (res' * res) / (yc' * yc);
endfunction

[n, k, data] = parse_input (read_stdin ());
[beta, r2] = ols_fit (data(:, 1:k), data(:, k + 1));
fprintf ("%.15g\n", [beta; r2]);
