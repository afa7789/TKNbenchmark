#!/usr/bin/env Rscript
# linreg: ordinary least-squares regression read from standard input.
#
# Input:  "n k" header, then n rows of k feature values followed by y.
# Output: b0, b1, ..., bk, then R^2, one per line.

read_problem <- function(con) {
  header <- scan(con, what = integer(), n = 2L, quiet = TRUE)
  if (length(header) != 2L || anyNA(header)) {
    stop("Can't read the `n k` header line.", call. = FALSE)
  }
  n <- header[[1L]]
  k <- header[[2L]]
  values <- scan(con, what = double(), n = n * (k + 1L), quiet = TRUE)
  if (length(values) != n * (k + 1L)) {
    stop(sprintf("Expected %d values, got %d.", n * (k + 1L), length(values)),
         call. = FALSE)
  }
  # Rows are stored contiguously, so fill a (k + 1) x n matrix and transpose.
  data <- t(matrix(values, nrow = k + 1L, ncol = n))
  list(x = data[, seq_len(k), drop = FALSE], y = data[, k + 1L])
}

# Fit on centred data for numerical stability, then recover the intercept.
fit_ols <- function(x, y) {
  x_mean <- colMeans(x)
  y_mean <- mean(y)
  xc <- sweep(x, 2L, x_mean, check.margin = FALSE)
  yc <- y - y_mean
  fit <- .lm.fit(xc, yc)
  if (fit$rank < ncol(x)) {
    stop("The design matrix is rank deficient.", call. = FALSE)
  }
  slopes <- numeric(ncol(x))
  slopes[fit$pivot] <- fit$coefficients
  ss_res <- sum(fit$residuals^2)
  ss_tot <- sum(yc^2)
  list(
    coefficients = c(y_mean - sum(slopes * x_mean), slopes),
    r_squared = 1 - ss_res / ss_tot
  )
}

main <- function() {
  con <- file("stdin", open = "r")
  on.exit(close(con), add = TRUE)
  problem <- read_problem(con)
  fit <- fit_ols(problem$x, problem$y)
  out <- c(fit$coefficients, fit$r_squared)
  writeLines(sprintf("%.15g", out))
}

main()
