#!/usr/bin/env Rscript
# linreg: ordinary least-squares regression with intercept, reporting R^2.
#
# Input (stdin): header "n k", then n rows of k features followed by y.
# Output (stdout): b0, b1, ..., bk, R^2 -- one per line.

read_input <- function(con) {
  header <- scan(con, what = integer(), n = 2L, quiet = TRUE)
  if (length(header) != 2L) stop("missing header line 'n k'")
  n <- header[[1L]]
  k <- header[[2L]]
  p <- k + 1L

  values <- scan(con, what = double(), n = n * p, quiet = TRUE)
  if (length(values) != n * p) {
    stop(sprintf("expected %d values, got %d", n * p, length(values)))
  }
  data <- matrix(values, nrow = p, ncol = n)  # column i holds row i of the input
  rm(values)

  list(x = t(data[seq_len(k), , drop = FALSE]), y = data[p, ])
}

# Fit y ~ b0 + X b on centred data for numerical stability; the intercept is
# recovered from the column means.
fit_ols <- function(x, y) {
  x_mean <- colMeans(x)
  y_mean <- mean(y)
  xc <- sweep(x, 2L, x_mean, check.margin = FALSE)
  yc <- y - y_mean

  decomposition <- qr(xc, LAPACK = FALSE)
  if (decomposition$rank < ncol(xc)) stop("design matrix is rank deficient")
  slopes <- qr.coef(decomposition, yc)
  residuals <- qr.resid(decomposition, yc)

  ss_res <- sum(residuals^2)
  ss_tot <- sum(yc^2)

  list(
    coefficients = c(y_mean - sum(x_mean * slopes), slopes),
    r_squared = 1 - ss_res / ss_tot
  )
}

main <- function() {
  con <- file("stdin", open = "r")
  on.exit(close(con))
  input <- read_input(con)
  fit <- fit_ols(input$x, input$y)
  out <- c(fit$coefficients, fit$r_squared)
  writeLines(formatC(out, digits = 15, format = "g"))
}

main()
