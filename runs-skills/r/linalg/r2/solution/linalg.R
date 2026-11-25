#!/usr/bin/env Rscript
# linalg: log-determinant, linear solve, eigenvalues and Frobenius norm
# of a symmetric positive-definite matrix read from standard input.

read_problem <- function(con = file("stdin")) {
  tokens <- scan(con, what = double(), quiet = TRUE)
  if (length(tokens) < 1L) stop("Can't read `n`: input is empty.")
  n <- as.integer(tokens[[1L]])
  if (is.na(n) || n < 1L) stop("`n` must be a positive integer.")
  need <- 1L + n * n + n
  if (length(tokens) < need) {
    stop(sprintf("Expected %d numbers after `n`, got %d.", need - 1L, length(tokens) - 1L))
  }
  a <- matrix(tokens[seq.int(2L, length.out = n * n)], nrow = n, ncol = n, byrow = TRUE)
  b <- tokens[seq.int(2L + n * n, length.out = n)]
  list(a = a, b = b)
}

analyse <- function(a, b) {
  r <- tryCatch(chol(a), error = function(e) NULL)
  if (is.null(r)) {
    # Not numerically PD: fall back to general LU-based routines.
    log_det <- as.numeric(determinant(a, logarithm = TRUE)$modulus)
    x <- solve(a, b)
  } else {
    log_det <- 2 * sum(log(diag(r)))
    x <- backsolve(r, forwardsolve(r, b, upper.tri = TRUE, transpose = TRUE))
  }
  list(
    log_det = log_det,
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
  problem <- read_problem()
  res <- analyse(problem$a, problem$b)
  writeLines(vapply(res, format_numbers, character(1)))
}

main()
