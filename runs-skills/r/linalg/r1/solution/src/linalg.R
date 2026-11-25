#!/usr/bin/env Rscript
# linalg: log-determinant, linear solve, eigenvalues and Frobenius norm of a
# symmetric positive-definite matrix read from standard input.

read_problem <- function(con) {
  tokens <- scan(con, what = double(), quiet = TRUE)
  if (length(tokens) < 1L) stop("Can't read `n` from input.", call. = FALSE)
  n <- as.integer(tokens[[1L]])
  needed <- 1L + n * n + n
  if (is.na(n) || n < 1L || length(tokens) < needed) {
    stop("Input must contain `n`, an n x n matrix and a vector of length n.", call. = FALSE)
  }
  a <- matrix(tokens[seq.int(2L, length.out = n * n)], nrow = n, ncol = n, byrow = TRUE)
  b <- tokens[seq.int(2L + n * n, length.out = n)]
  list(a = a, b = b)
}

analyse <- function(a, b) {
  sym <- (a + t(a)) / 2
  r <- tryCatch(chol(sym), error = function(e) NULL)
  if (is.null(r)) {
    # Not numerically SPD: fall back to an LU-based path.
    log_det <- as.numeric(determinant(sym, logarithm = TRUE)$modulus)
    x <- solve(sym, b)
  } else {
    log_det <- 2 * sum(log(diag(r)))
    x <- backsolve(r, forwardsolve(r, b, upper.tri = TRUE, transpose = TRUE))
  }
  eig <- eigen(sym, symmetric = TRUE, only.values = TRUE)$values
  list(
    log_det = log_det,
    x = as.vector(x),
    eigenvalues = sort(eig),
    frobenius = sqrt(sum(a * a))
  )
}

fmt <- function(v) paste(sprintf("%.15g", v), collapse = " ")

main <- function() {
  con <- file("stdin")
  on.exit(close(con), add = TRUE)
  p <- read_problem(con)
  res <- analyse(p$a, p$b)
  writeLines(c(fmt(res$log_det), fmt(res$x), fmt(res$eigenvalues), fmt(res$frobenius)))
}

main()
