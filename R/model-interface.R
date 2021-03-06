#' Modeling interface for trendbreaker
#'
#' These functions wrappers around various modelling tools to ensure a
#' consistent input for *trendbreaker* functions. See details for available model
#' interfaces.
#'
#' @details The following interfaces are available:
#'
#' * `lm_model`: interface for linear models implemented in [`stats::lm`](stats::lm)
#'
#' * `glm_model`: interface for generalised linear models (GLMs) implemented in
#' `[stats::glm](stats::glm)`
#'
#' * `glm_nb_model`: interface for negative binomial generalied linear models
#' implemented in [`MASS::glm_nb`](MASS::glm_nb)
#'
#' * `brms_model`: interface for Bayesian regression models implemented in
#' [`brms::brm`](brms::brm)
#'
#' @param formula the formula of the model, with the response variable on the
#'   left of a tilde symbol, and predictors on the right hand-side; variable
#'   names used in the formula will need to be matched by columns in the `data`
#'   input to other functions
#'
#' @param family the model family to be used for the response variable
#'
#' @param x an `trendbreaker_model` object
#'
#' @param ... further arguments passed to other methods: `lm` for `lm_model`,
#'   `glm` for `glm_model`, `MASS::glm_nb` for `glm_nb_model`, `brms::brm` for
#'   `brms_model`
#'
#' @return  An `trendbreaker_model` object (S3 class inheriting `list`), containing items
#'   which can be accessed by various accessors - see `?trendbreaker_model-accessors`
#'
#' @author Dirk Schumacher
#'
#' @aliases trendbreaker_model trendbreaker_models
#'
#' @export
#' @rdname trendbreaker_model
#' @aliases glm_model
glm_model <- function(formula, family, ...) {
  structure(
    eval(bquote(list(
      model_class = "glm",
      train = function(data) {
        model <- glm(formula = .(formula), family = .(family), data = data, ...)
        model_fit(model, formula)
      }
    ))),
    class = c("trendbreaker_glm", "trendbreaker_model")
  )
}



#' @export
#' @rdname trendbreaker_model
#' @aliases glm_nb_model
glm_nb_model <- function(formula, ...) {
  structure(
    eval(bquote(list(
      model_class = "MASS::glm.nb",
      train = function(data) {
        model <- MASS::glm.nb(formula = .(formula), data = data, ...)
        model_fit(model, formula)
      }
    ))),
    class = c("trendbreaker_glm_nb", "trendbreaker_model")
  )
}



#' @export
#' @rdname trendbreaker_model
#' @aliases lm_model
lm_model <- function(formula, ...) {
  structure(
    eval(bquote(list(
      model_class = "lm",
      train = function(data) {
        model <- lm(formula = .(formula), data = data, ...)
        model_fit(model, formula)
      }
    ))),
    class = c("trendbreaker_lm", "trendbreaker_model")
  )
}



#' @export
#' @rdname trendbreaker_model
#' @aliases brms_model
brms_model <- function(formula, family, ...) {
  structure(
    eval(bquote(list(
      model_class = "brms",
      train = function(data) {
        model <- brms::brm(
          formula = .(formula),
          data = data,
          family = .(family), ...
        )
        res <- list(
          model = model,
          predict = function(newdata, alpha = 0.05) {
            res <- add_prediction_interval(
              data = newdata,
              model = model,
              alpha = alpha
            )
            col_name <- as.character(formula[[2]])
            append_observed_column(res, res[[col_name]])
          }
        )
        class(res) <- c("trendbreaker_model_fit", class(res))
        res
      }
    ))),
    class = c("trendbreaker_brms_nb", "trendbreaker_model")
  )
}



#' @export
#' @rdname trendbreaker_model
#' @aliases format.trendbreaker_model
format.trendbreaker_model <- function(x, ...) {
  paste0("Untrained trendbreaker model type: ", x[["model_class"]])
}



#' @export
#' @rdname trendbreaker_model
#' @aliases print.trendbreaker_model
print.trendbreaker_model <- function(x, ...) {
  cat(format(x, ...))
}





# =============
# = INTERNALS =
# =============
add_prediction_interval <- function(model, data, alpha) {
  UseMethod("add_prediction_interval")
}

add_prediction_interval.negbin <- function(model, data, alpha) {
  mu <- predict(model, newdata = data, type = "response")
  theta <- model$theta
  stopifnot(theta > 0)
  # this ignores the uncertainty around mu and theta
  dplyr::bind_cols(
    data,
    tibble::tibble(
      pred = mu,
      lower = stats::qnbinom(alpha / 2, mu = mu, size = theta),
      upper = stats::qnbinom(1 - alpha / 2, mu = mu, size = theta),
    )
  )
}

add_prediction_interval.brmsfit <- function(model, data, alpha) {
  fit <- predict(model, data)
  interval <- brms::predictive_interval(
    model,
    newdata = data,
    prob = 1 - alpha
  )
  dplyr::bind_cols(
    data,
    tibble::tibble(
      pred = fit[, 1],
      lower = interval[, 1],
      upper = interval[, 2]
    )
  )
}

add_prediction_interval.default <- function(model, data, alpha) {
  suppressWarnings(
    ciTools::add_pi(
      tb = data,
      fit = model,
      alpha = alpha,
      names = c("lower", "upper")
    )
  )
}

model_fit <- function(model, formula) {
  out <- list(
    model = model,
    predict = function(newdata, alpha = 0.05) {
      suppressWarnings(
        res <- add_prediction_interval(
          data = newdata,
          model = model,
          alpha = alpha
        )
      )
      col_name <- as.character(formula[[2]])
      append_observed_column(res, res[[col_name]])
    }
  )
  class(out) <- c("trendbreaker_model_fit", class(out))
  out
}

append_observed_column <- function(data, value) {
  data[["observed"]] <- value
  data
}
