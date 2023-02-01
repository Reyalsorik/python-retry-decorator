#!/usr/bin/env python3

"""Contains the logic for handling a retry and logging retries after an unexpected exception/result is captured."""

import logging
import socket
import traceback
from functools import wraps
from typing import Any, Tuple, Type, Union

import tenacity

from retry_decorator.lib.exceptions import RetryError


def get_retry_exceptions() -> tuple:
    """Get the exception types that are permitted for retry."""
    return (
        socket.timeout,
        BrokenPipeError,
        ConnectionResetError
    )


def retry_on_exceptions(exceptions: Union[Tuple[Type[BaseException], ...], Type[BaseException]] = tuple()) -> tenacity.retry_if_exception_type:
    """Retry permitted exceptions.

    :param exceptions: exceptions to permit
    """
    return tenacity.retry_if_exception_type(exceptions or get_retry_exceptions())


def retry_on_false() -> tenacity.retry_base:
    """Retry on false results."""
    return tenacity.retry_if_result(lambda value: value is False)


class Retry(object):
    """Decorator for retrying and logging retries after an unexpected exception/result is captured."""

    def __init__(self, retry: tenacity.retry_base = tenacity.retry_if_exception_type(BaseException), retries: int = 3, wait: int = 3, wait_before: int = 0, jitter: bool = False, logger_name: str = "") -> None:
        """Initialize.

        :param retry: retry condition
        :param retries: amount of retries
        :param wait: wait time between retries
        :param wait_before: wait time before execution
        :param jitter: whether to include random jitter
        """
        self.logger = logging.getLogger(logger_name)
        self.retry = retry
        self.retries = retries
        self.wait = wait
        self.wait_before = wait_before
        self.jitter = jitter
        self.max_default_wait = 10
        self.function = None

    def __call__(self, function: Any, *args, **kwargs) -> Any:
        """Callable.

        :param function: function to retry
        """
        self.function = function
        if self.function is None:
            raise TypeError(f"{self.__class__.__name__} takes 0 positional arguments but 1 was given, did you mean 'Retry()'?")  # Decorator must be called

        @wraps(self.function)
        def retry_wrapper(*wrapped_args, **wrapped_kwargs):
            """Wrap the function + arguments in a retry decorator."""
            return tenacity.retry(
                retry=self.retry,
                stop=tenacity.stop_after_attempt(self.retries),
                wait=self._get_wait(),
                before_sleep=tenacity.nap.sleep(self.wait_before),
                reraise=True,  # Always re-raise exceptions
                retry_error_callback=self.error_callback,
                after=self.log_retry
            )(self.function)(*wrapped_args, **wrapped_kwargs)

        return retry_wrapper

    def _get_wait(self) -> Union[tenacity.wait_exponential, tenacity.wait_random]:
        """Get the amount of time to wait between retries."""
        wait = tenacity.wait_exponential(  # 2^n * 2 seconds; start, max; 2, 4, 8, 10, ...
            multiplier=2,
            min=self.wait,
            max=max(self.wait, self.max_default_wait)
        )
        if self.jitter:
            wait = tenacity.wait_random(  # random; between min, max
                min=self.wait,
                max=max(self.wait, self.max_default_wait)
            )
        return wait

    def error_callback(self, retry_state: tenacity.RetryCallState) -> None:
        """Raise an exception when a retry occurs.

        :param retry_state: call state of the retry
        """
        raise RetryError(self.logger, getattr(self.function, "__name__"), retry_state.attempt_number)

    def log_retry(self, retry_state: tenacity.RetryCallState) -> None:
        """Log when a retry occurs.

        :param retry_state: call state of the retry
        """
        if retry_state.outcome.failed:
            exc_info = retry_state.outcome.exception()
            formatted_exception = "".join(
                traceback.format_exception(
                    type(exc_info),
                    value=exc_info,
                    tb=exc_info.__traceback__
                )
            )
            verb, result = "raised", f"{exc_info.__class__.__name__}"
            result = result if retry_state.attempt_number < self.retries else f"{result}: \n{formatted_exception.strip()}"
        else:
            verb, result = "returned", retry_state.outcome.result()
        self.logger.warning(f"Retry {getattr(self.function, '__name__')} #{retry_state.attempt_number}/{self.retries}, {verb}: {result}")
