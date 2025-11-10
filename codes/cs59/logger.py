#!/usr/bin/env python

"""
Logging configuration for the project.

This module sets up the logging format and levels for the project.
It uses the standard logging library to create a logger that outputs formatted
log messages to the console. It is recommended to use this module at the
beginning of your scripts to ensure consistent logging across the analysis.
"""

import os, sys, re, warnings
from pathlib import Path
import logging

## Config variables ## ---------------------------------------------------------
LOGGER_FORMAT = "[%(asctime)s] %(levelname)-4s %(name)s [%(filename)s:%(funcName)s:%(lineno)d] %(message)s"
DATE_FORMAT = "%Y-%m-%d %H:%M:%S"
_HANDLER_NAME = "setup_stream_handler"

LEVEL_COLORS = {
    logging.DEBUG:    "\033[1;34m",  # blue bold
    logging.INFO:     "\033[0;32m",  # green
    logging.WARNING:  "\033[1;33m",  # yellow bold
    logging.ERROR:    "\033[0;31m",  # red
    logging.CRITICAL: "\033[1;31m",  # red bold
}
RESET = "\033[0m"

## Functions ## ----------------------------------------------------------------
def _repo_root() -> Path | None:
    import subprocess
    try:
        out = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        ).stdout.strip()
        p = Path(out)
        return p if p.exists() else None
    except Exception:
        return None

def _project_name(repo_root: Path | None, exclude: str = "_|-") -> str:
    """Return styled project name from repo root or cwd."""
    name = (repo_root or Path.cwd()).name or "App"
    if re.findall(exclude, name): name = re.sub(exclude, " ", name).title()
    return name

def _hide_base_path(repo_root: Path | None, ignore: list[str] | None = None) -> str:
    """Return a cwd string with some superfluous base paths removed."""
    cwd = str(repo_root or Path.cwd().resolve())
    # Build default ignore list if none provided
    if ignore is None:
        user = os.environ.get('USER', os.environ.get('USERNAME', ''))
        ignore = [rf".*{re.escape(user)}"]
        ignore.extend([r"\.os\.py", r".*mamba", r".*conda", r".*projects"])
    # Apply filters sequentially
    for pat in ignore: cwd = re.sub(pat, "", cwd)
    # Fallback: collapse to last 2 parts if result is empty
    if not cwd.strip(): cwd = str(Path(*Path.cwd().parts[-2:]))
    return cwd

def _is_nested(logger: logging.Logger, stream=sys.stdout) -> bool:
    """Return True if a StreamHandler created by setup_logger() is already attached."""
    for h in logger.handlers:
        # Check both the handler name and that it's a StreamHandler
        if isinstance(h, logging.StreamHandler) and h.get_name() == _HANDLER_NAME:
            # ensure we're looking at the same stream
            if getattr(h, "stream", None) is stream:
                return True
            # If you don't care about stream identity, just `return True` here.
            return True
    return False  

class _ColorFormatter(logging.Formatter):
    def __init__(self, fmt: str, datefmt: str, use_color: bool) -> None:
        super().__init__(fmt=fmt, datefmt=datefmt)
        self.use_color = use_color

    def format(self, record: logging.LogRecord) -> str:
        if self.use_color:
            color = LEVEL_COLORS.get(record.levelno, "")
            if color:
                record.levelname = f"{color}{record.levelname}{RESET}"
        else:
            # raise warning if color is requested but not supported
            if any(code in record.levelname for code in LEVEL_COLORS.values()):
                warnings.warn("Color codes in log level names but color not supported.")
        return super().format(record)

def _stream_supports_color(stream: object) -> bool:
    """Respect NO_COLOR; require TTY"""
    if os.environ.get("NO_COLOR"): return False
    if hasattr(stream, "isatty"): return stream.isatty()
    return False

def reset_logging(force: bool = False) -> None:
    """
    Remove all handlers and filters from the root logger and its descendants,
    so logging can be cleanly reconfigured. Works with Python 3.8+.

    Parameters:
        force: if True, also clears custom loggers (not just root).
               Useful for full reinit (e.g., in notebooks or tests).
    """
    if not force and hasattr(logging, "basicConfig"):
        # basicConfig(force=True) would do the same but we want manual control
        pass

    # Clear root handlers
    root = logging.getLogger()
    for handler in root.handlers[:]:
        root.removeHandler(handler)
    for flt in root.filters[:]:
        root.removeFilter(flt)

    # Optionally clear all named loggers
    if force:
        for name in list(logging.Logger.manager.loggerDict.keys()):
            logger = logging.getLogger(name)
            if isinstance(logger, logging.PlaceHolder):
                continue
            for handler in logger.handlers[:]:
                logger.removeHandler(handler)
            for flt in logger.filters[:]:
                logger.removeFilter(flt)
            logger.propagate = True
            logger.setLevel(logging.NOTSET)

    # Reset the logging level and root settings
    root.setLevel(logging.NOTSET)
    logging.captureWarnings(False)

def setup_logger(level: int = logging.INFO, stream = sys.stdout) -> logging.Logger:
    logger_name = _project_name(_repo_root())
    # Root/logger setup without global side effects
    logger = logging.getLogger(logger_name)
    logger.setLevel(level)
    logger.propagate = False
    # Avoid duplicate handlers if setup_logger() is called multiple times
    if not _is_nested(logger, stream=stream):
        handler = logging.StreamHandler(stream)
        handler.set_name(_HANDLER_NAME)  # marker
        handler.setLevel(level)
        handler.setFormatter(
            _ColorFormatter(
                LOGGER_FORMAT, DATE_FORMAT, _stream_supports_color(stream)
            )
        )
        logger.addHandler(handler)
    # Show where the script is running from
    logger.info("Working at %s", _hide_base_path(_repo_root()))
    return logger

## Set up the logger ## --------------------------------------------------------
# reset_logging(force=True) or importlib.reload(logger)
logger = setup_logger(level=logging.INFO)

## logger and shorthands ## ----------------------------------------------------
info = logger.info
warning = logger.warning
debug = logger.debug
error = logger.error
critical = logger.critical

## Suppress specific warnings ## -----------------------------------------------
warnings.simplefilter(action="ignore", category=FutureWarning)
warnings.simplefilter(action="ignore", category=UserWarning)
