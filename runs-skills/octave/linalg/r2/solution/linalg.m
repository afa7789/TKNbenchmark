## -*- texinfo -*-
## @deftypefn {} {} linalg ()
## Read a symmetric positive-definite matrix @var{A} and a vector @var{b}
## from standard input and print ln(det A), the solution of A x = b, the
## ascending eigenvalues of A and its Frobenius norm.
## @end deftypefn

function linalg ()
  vals = sscanf (fread (stdin, Inf, "*char")', "%f");
  if (isempty (vals))
    error ("linalg: missing matrix size");
  endif

  n = round (vals(1));
  if (n < 1 || numel (vals) < 1 + n*n + n)
    error ("linalg: expected %d matrix entries and %d vector entries", n*n, n);
  endif

  A = reshape (vals(2:1+n*n), n, n)';
  b = vals(2+n*n:1+n*n+n);
  A = (A + A') / 2;

  [R, p] = chol (A);
  if (p == 0)
    logdet = 2 * sum (log (diag (R)));
    x = R \ (R' \ b);
  else
    ## Not numerically positive definite: fall back to an LU-based solution.
    [~, U] = lu (A);
    logdet = sum (log (abs (diag (U))));
    x = A \ b;
  endif

  ev = sort (eig (A));

  fprintf ("%.15g\n", logdet);
  print_row (x);
  print_row (ev);
  fprintf ("%.15g\n", norm (A, "fro"));
endfunction

function print_row (v)
  s = sprintf ("%.15g ", v);
  fprintf ("%s\n", s(1:end-1));
endfunction
