function linalg ()
  ## Read an SPD system from stdin and print ln(det A), x, eig(A), ||A||_F.
  text = fread (stdin, Inf, "char=>char")';
  vals = sscanf (text, "%f");
  if (isempty (vals))
    error ("linalg: empty input");
  endif

  n = vals(1);
  if (n != fix (n) || n < 1 || numel (vals) < 1 + n*n + n)
    error ("linalg: malformed input");
  endif

  A = reshape (vals(2:1+n*n), n, n).';
  b = vals(2+n*n:1+n*n+n);
  A = (A + A.') / 2;   # enforce exact symmetry

  [R, p] = chol (A);
  if (p == 0)
    logdet = 2 * sum (log (diag (R)));
    x = R \ (R.' \ b);
  else
    ## Fall back for numerically indefinite input.
    [~, U] = lu (A);
    logdet = sum (log (abs (diag (U))));
    x = A \ b;
  endif

  ev = sort (eig (A));
  fro = norm (A, "fro");

  printf ("%s\n", fmt (logdet));
  printf ("%s\n", fmt (x));
  printf ("%s\n", fmt (ev));
  printf ("%s\n", fmt (fro));
endfunction

function s = fmt (v)
  s = strtrim (sprintf ("%.15g ", v));
endfunction
