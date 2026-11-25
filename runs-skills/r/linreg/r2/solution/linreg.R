#!/usr/bin/env Rscript
# linreg: ordinary least-squares regression with intercept, reading from stdin.

read_problem <- function(con) {
  header <- scan(con, what = integer(), n = 2L, quiet = TRUE)
  if (length(header) != 2L) stop("Can't read header `n k`.", call. = FALSE)
  n <- header[[1L]]
  k <- header[[2L]]
  values <- scan(con, what = double(), n = n * (k + 1L), quiet = TRUE)
  if (length(values) != n * (k + 1L)) {
    stop(sprintf("Expected %d values, got %d.", n * (k + 1L), length(values)), call. = FALSE)
  }
  data <- matrix(values, nrow = n, ncol = k + 1L, byrow = TRUE)
  list(x = data[, seq_len(k), drop = FALSE], y = data[, k + 1L])
}

# Fit on centred data for numerical stability, then recover the intercept.
fit_ols <- function(x, y) {
  x_mean <- colMeans(x)
  y_mean <- mean(y)
  xc <- sweep(x, 2L, x_mean, check.margin = FALSE)
  yc <- y - y_mean
  fit <- .lm.fit(xc, yc)
  slopes <- fit$coefficients
  intercept <- y_mean - sum(x_mean * slopes)
  ss_res <- sum(fit$residuals^2)
  ss_tot <- sum(yc^2)
  list(coefficients = c(intercept, slopes), r_squared = 1 - ss_res / ss_tot)
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
