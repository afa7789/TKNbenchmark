## -*- texinfo -*-
## @deftypefn {} {} linalg_main ()
## Read a symmetric positive-definite system from standard input and print
## ln(det A), the solution of A x = b, the ascending eigenvalues of A and
## its Frobenius norm, one item per line.
## @end deftypefn

function linalg_main ()
  [A, b] = read_system (stdin);

  ## Use only the upper triangle so tiny input asymmetries cannot skew results.
  A = triu (A) + triu (A, 1).';

  [R, p] = chol (A);
  if (p == 0)
    logdet = 2 * sum (log (diag (R)));
    x = R \ (R.' \ b);
  else
    ## Not numerically positive definite: fall back to an LU factorization.
    [L, U, P] = lu (A);
    logdet = sum (log (abs (diag (U))));
    x = U \ (L \ (P * b));
  endif

  ev = sort (eig (A), "ascend");

  print_row (logdet);
  print_row (x);
  print_row (ev);
  print_row (norm (A, "fro"));
endfunction

function [A, b] = read_system (fid)
  vals = fscanf (fid, "%f");
  if (isempty (vals))
    error ("linalg_main: missing matrix size");
  endif
  n = round (vals(1));
  if (n < 1 || numel (vals) < 1 + n * n + n)
    error ("linalg_main: expected %d matrix entries and %d vector entries",
           n * n, n);
  endif
  A = reshape (vals(2:1 + n * n), n, n).';
  b = vals(2 + n * n:1 + n * n + n);
endfunction

function print_row (v)
  s = sprintf ("%.15g ", v);
  fprintf ("%s\n", s(1:end-1));
endfunction
