#!/usr/bin/env Rscript
# linalg: dense linear algebra on a symmetric positive-definite matrix.
# Reads n, the n x n matrix A, and a vector b from stdin; prints
# ln(det A), the solution of A x = b, ascending eigenvalues, and ||A||_F.

read_input <- function(con) {
  tokens <- scan(con, what = double(), quiet = TRUE)
  if (length(tokens) < 1L) stop("empty input", call. = FALSE)
  n <- as.integer(tokens[1L])
  if (is.na(n) || n < 1L) stop("invalid dimension", call. = FALSE)
  needed <- 1L + n * n + n
  if (length(tokens) < needed) stop("input too short", call. = FALSE)
  a <- matrix(tokens[2L:(1L + n * n)], nrow = n, ncol = n, byrow = TRUE)
  b <- tokens[(2L + n * n):needed]
  list(a = a, b = b)
}

fmt <- function(x) paste(sprintf("%.15g", x), collapse = " ")

main <- function() {
  con <- file("stdin")
  on.exit(close(con))
  input <- read_input(con)
  a <- input$a
  # Symmetrize to remove any rounding asymmetry in the printed input.
  a <- (a + t(a)) / 2

  r <- chol(a)                       # A = R'R, R upper triangular
  log_det <- 2 * sum(log(diag(r)))
  x <- backsolve(r, forwardsolve(t(r), input$b))
  eig <- sort(eigen(a, symmetric = TRUE, only.values = TRUE)$values)
  frob <- norm(input$a, type = "F")

  writeLines(c(fmt(log_det), fmt(x), fmt(eig), fmt(frob)))
}

main()
