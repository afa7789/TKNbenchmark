#!/usr/bin/env Rscript
# linreg: ordinary least-squares regression read from standard input.
#
# Input:  "n k" header, then n rows of k features followed by the response.
# Output: b0, b1, ..., bk and R^2, one per line.

read_problem <- function(con) {
  header <- scan(con, what = integer(), n = 2L, quiet = TRUE)
  if (length(header) != 2L || anyNA(header)) {
    stop("Can't read the `n k` header line.", call. = FALSE)
  }
  n <- header[[1L]]
  k <- header[[2L]]
  p <- k + 1L
  values <- scan(con, what = double(), n = n * p, quiet = TRUE)
  if (length(values) != n * p) {
    stop(sprintf("Expected %d values, got %d.", n * p, length(values)),
         call. = FALSE)
  }
  data <- matrix(values, nrow = n, ncol = p, byrow = TRUE)
  list(x = data[, seq_len(k), drop = FALSE], y = data[, p])
}

fit_ols <- function(x, y) {
  # Householder QR on the design matrix is numerically stable even for
  # poorly scaled or nearly collinear features.
  design <- cbind(1, x)
  fit <- stats::lm.fit(design, y)
  ss_res <- sum(fit$residuals^2)
  ss_tot <- sum((y - mean(y))^2)
  list(coefficients = unname(fit$coefficients), r_squared = 1 - ss_res / ss_tot)
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
