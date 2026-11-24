function linalg ()
  % LINALG  Read an SPD system from stdin; print ln(det A), A\b, eig(A), ||A||_F.
  txt = fread (stdin, Inf, "char=>char")';
  vals = sscanf (txt, "%f");
  if (isempty (vals))
    error ("linalg: empty input");
  endif
  n = round (vals(1));
  if (n < 1 || numel (vals) < 1 + n*n + n)
    error ("linalg: expected %d matrix entries and %d vector entries", n*n, n);
  endif

  A = reshape (vals(2:1+n*n), n, n)';   % rows were given in row-major order
  b = vals(2+n*n:1+n*n+n);
  A = (A + A') / 2;                     % enforce exact symmetry

  [R, p] = chol (A);
  if (p == 0)
    logdet = 2 * sum (log (diag (R)));
    x = R \ (R' \ b);
  else
    % Not numerically positive definite: fall back to LU.
    [L, U, P] = lu (A);
    logdet = sum (log (abs (diag (U))));
    x = U \ (L \ (P * b));
  endif

  ev = sort (eig (A));
  fro = norm (A, "fro");

  printf ("%.15g\n", logdet);
  print_row (x);
  print_row (ev);
  printf ("%.15g\n", fro);
endfunction

function print_row (v)
  s = sprintf ("%.15g ", v);
  printf ("%s\n", s(1:end-1));
endfunction
