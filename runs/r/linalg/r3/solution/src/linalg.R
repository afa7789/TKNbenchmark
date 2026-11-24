#!/usr/bin/env Rscript
# linalg: log-determinant, linear solve, eigenvalues and Frobenius norm of a
# symmetric positive-definite matrix read from standard input (see SPEC.md).

read_problem <- function(con) {
  tokens <- scan(con, what = double(), quiet = TRUE)
  if (length(tokens) < 1L) stop("empty input", call. = FALSE)
  n <- as.integer(tokens[1L])
  if (is.na(n) || n < 1L) stop("invalid dimension", call. = FALSE)
  needed <- 1L + n * n + n
  if (length(tokens) < needed) stop("not enough numbers in input", call. = FALSE)
  a <- matrix(tokens[2L:(1L + n * n)], nrow = n, ncol = n, byrow = TRUE)
  b <- tokens[(2L + n * n):needed]
  list(a = a, b = b)
}

analyse <- function(a, b) {
  # Symmetrise to remove rounding asymmetry in the textual input.
  a <- (a + t(a)) / 2
  r <- tryCatch(chol(a), error = function(e) NULL)
  if (!is.null(r)) {
    logdet <- 2 * sum(log(diag(r)))
    x <- backsolve(r, forwardsolve(r, b, upper.tri = TRUE, transpose = TRUE))
  } else {
    # Numerically not positive-definite: fall back to an LU factorisation.
    logdet <- as.numeric(determinant(a, logarithm = TRUE)$modulus)
    x <- solve(a, b)
  }
  list(
    logdet = logdet,
    x = as.vector(x),
    eigenvalues = sort(eigen(a, symmetric = TRUE, only.values = TRUE)$values),
    frobenius = sqrt(sum(a * a))
  )
}

format_numbers <- function(v) {
  out <- sprintf("%.15g", v)
  out[out == "-0"] <- "0"
  paste(out, collapse = " ")
}

main <- function() {
  con <- file("stdin")
  on.exit(close(con))
  p <- read_problem(con)
  res <- analyse(p$a, p$b)
  writeLines(c(
    format_numbers(res$logdet),
    format_numbers(res$x),
    format_numbers(res$eigenvalues),
    format_numbers(res$frobenius)
  ))
}

main()
