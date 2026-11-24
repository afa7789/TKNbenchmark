#!/usr/bin/env Rscript
# linalg: log-determinant, linear solve, eigenvalues and Frobenius norm of an
# SPD matrix read from standard input. See SPEC.md.

read_input <- function(con = file("stdin")) {
  tokens <- scan(con, what = double(), quiet = TRUE)
  if (length(tokens) < 1L) stop("empty input", call. = FALSE)
  n <- as.integer(tokens[1L])
  if (is.na(n) || n < 1L) stop("invalid matrix size", call. = FALSE)
  needed <- 1L + n * n + n
  if (length(tokens) < needed) stop("not enough numbers in input", call. = FALSE)
  a <- matrix(tokens[2L:(1L + n * n)], nrow = n, ncol = n, byrow = TRUE)
  b <- tokens[(2L + n * n):needed]
  list(a = a, b = b)
}

fmt <- function(x) {
  x[x == 0] <- 0  # normalise negative zero
  paste(trimws(formatC(x, digits = 15L, format = "g")), collapse = " ")
}

main <- function() {
  input <- read_input()
  a <- input$a
  a <- (a + t(a)) / 2  # enforce exact symmetry
  r <- chol(a)
  log_det <- 2 * sum(log(diag(r)))
  x <- backsolve(r, forwardsolve(t(r), input$b))
  eig <- sort(eigen(a, symmetric = TRUE, only.values = TRUE)$values)
  frob <- norm(a, type = "F")
  writeLines(c(fmt(log_det), fmt(x), fmt(eig), fmt(frob)))
}

invisible(main())
