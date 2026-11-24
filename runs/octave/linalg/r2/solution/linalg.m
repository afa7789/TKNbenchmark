## linalg.m -- dense linear algebra on a symmetric positive-definite matrix.
##
## Reads n, the n-by-n SPD matrix A and the vector b from standard input, then
## prints ln(det A), the solution of A*x = b, the ascending eigenvalues of A and
## the Frobenius norm of A.

1;

function [A, b] = read_input (fid)
  txt = fread (fid, Inf, "char=>char")';
  vals = sscanf (txt, "%f");
  if (isempty (vals))
    error ("linalg: empty input");
  endif
  n = round (vals(1));
  if (n < 1 || numel (vals) < 1 + n*n + n)
    error ("linalg: expected %d matrix entries and %d vector entries", n*n, n);
  endif
  A = reshape (vals(2:1+n*n), n, n)';
  b = vals(2+n*n:1+n*n+n);
endfunction

function print_row (fid, v)
  fprintf (fid, "%s\n", strtrim (sprintf ("%.15g ", v)));
endfunction

function main ()
  [A, b] = read_input (stdin);
  A = (A + A') / 2;            # enforce exact symmetry

  [R, p] = chol (A);
  if (p == 0)
    logdet = 2 * sum (log (diag (R)));
    x = R \ (R' \ b);
  else
    ## Not numerically SPD: fall back to LU.
    [L, U, P] = lu (A);
    logdet = sum (log (abs (diag (U))));
    x = A \ b;
  endif

  ev = sort (eig (A));

  fprintf ("%.15g\n", logdet);
  print_row (stdout, x);
  print_row (stdout, ev);
  fprintf ("%.15g\n", norm (A, "fro"));
endfunction

main ();
