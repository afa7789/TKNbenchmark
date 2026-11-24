#!/usr/bin/env Rscript
# linreg: ordinary least-squares regression read from standard input.
#
# Input:  "n k" header, then n rows of k feature values followed by y.
# Output: b0, b1, ..., bk, then R^2, one per line.

read_input <- function(con) {
  header <- scan(con, what = integer(), n = 2L, quiet = TRUE)
  if (length(header) != 2L) stop("missing 'n k' header", call. = FALSE)
  n <- header[[1L]]
  k <- header[[2L]]
  values <- scan(con, what = double(), n = n * (k + 1L), quiet = TRUE)
  if (length(values) != n * (k + 1L)) {
    stop(sprintf("expected %d values, got %d", n * (k + 1L), length(values)),
         call. = FALSE)
  }
  data <- matrix(values, nrow = n, ncol = k + 1L, byrow = TRUE)
  list(x = data[, seq_len(k), drop = FALSE], y = data[, k + 1L])
}

fit_ols <- function(x, y) {
  # Centre the columns so the intercept does not hurt conditioning, solve
  # the slopes by Householder QR, then recover the intercept.
  x_mean <- colMeans(x)
  y_mean <- mean(y)
  xc <- sweep(x, 2L, x_mean, check.margin = FALSE)
  yc <- y - y_mean
  fit <- .lm.fit(xc, yc, tol = 1e-12)
  slopes <- fit$coefficients[order(fit$pivot)]
  intercept <- y_mean - sum(x_mean * slopes)
  ss_res <- sum(fit$residuals^2)
  ss_tot <- sum(yc^2)
  list(coefficients = c(intercept, slopes), r_squared = 1 - ss_res / ss_tot)
}

main <- function() {
  con <- file("stdin", open = "r")
  on.exit(close(con))
  input <- read_input(con)
  fit <- fit_ols(input$x, input$y)
  out <- c(fit$coefficients, fit$r_squared)
  writeLines(sprintf("%.15g", out))
}

main()
