#!/usr/bin/env Rscript
# linalg: log-determinant, linear solve, eigenvalues and Frobenius norm of a
# symmetric positive-definite matrix read from standard input.

read_input <- function(con = file("stdin")) {
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
  r <- tryCatch(chol(a), error = function(e) NULL)
  if (is.null(r)) {
    # Not numerically positive-definite: fall back to an LU factorisation.
    logdet <- as.numeric(determinant(a, logarithm = TRUE)$modulus)
    x <- solve(a, b)
  } else {
    logdet <- 2 * sum(log(diag(r)))
    x <- backsolve(r, forwardsolve(t(r), b))
  }
  list(
    logdet = logdet,
    x = as.vector(x),
    eigenvalues = sort(eigen(a, symmetric = TRUE, only.values = TRUE)$values),
    frobenius = sqrt(sum(a * a))
  )
}

fmt <- function(v) paste(sprintf("%.15g", v), collapse = " ")

main <- function() {
  input <- read_input()
  res <- analyse(input$a, input$b)
  writeLines(c(fmt(res$logdet), fmt(res$x), fmt(res$eigenvalues), fmt(res$frobenius)))
}

main()
