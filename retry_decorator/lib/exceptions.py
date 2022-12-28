#!/usr/bin/env python3

"""Contains custom exceptions with additional functionality."""

import logging
from typing import Callable, Optional


class LogException(Exception):
    """Custom exception for logging exceptions before being raised."""

    def __init__(self, message: str, log: Callable = logging.getLogger().error) -> None:
        """Initialize.

        :param message: message to log
        :param log: logger callable
        """
        log(message)
        super().__init__(message)


class RetryError(LogException):
    """Custom exception for logging and raising an exception when a retry occurs."""

    def __init__(self, logger: logging.Logger, function_name: Optional[str], retry_attempts: int) -> None:
        """Initialize.

        :param logger: logger
        :param function_name: name of function
        :param retry_attempts: retry attempts
        """
        message = f"Function '{function_name}' failed; exceeded '{retry_attempts}' retries."
        super().__init__(message, logger.error)
