## linalg: dense linear algebra on a symmetric positive-definite matrix.
##
## Reads n, the n-by-n matrix A and the vector b from standard input and
## prints ln(det A), the solution of A*x = b, the ascending eigenvalues of A
## and the Frobenius norm of A, one per line.

1;

function [A, b] = read_problem (fid)
  vals = sscanf (fread (fid, Inf, "*char")', "%f");
  if (isempty (vals))
    error ("linalg: empty input");
  endif
  n = vals(1);
  if (n != fix (n) || n < 1 || numel (vals) < 1 + n*n + n)
    error ("linalg: malformed input");
  endif
  A = reshape (vals(2:1+n*n), n, n)';
  b = vals(2+n*n:1+n*n+n);
endfunction

function print_row (v)
  printf ("%s\n", strjoin (arrayfun (@(t) sprintf ("%.15g", t), v(:)', ...
                                     "UniformOutput", false), " "));
endfunction

function main ()
  [A, b] = read_problem (stdin);
  A = (A + A') / 2;                     # enforce exact symmetry
  [R, p] = chol (A);
  ev = sort (eig (A));
  if (p == 0)
    logdet = 2 * sum (log (diag (R)));
    x = R \ (R' \ b);
  else
    ## Numerically not positive definite: fall back to general methods.
    logdet = sum (log (abs (ev)));
    x = A \ b;
  endif
  printf ("%.15g\n", logdet);
  print_row (x);
  print_row (ev);
  printf ("%.15g\n", norm (A, "fro"));
endfunction

main ();
