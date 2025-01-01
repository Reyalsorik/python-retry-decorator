#!/usr/bin/env python3

from setuptools import setup

setup(
    setup_requires=["setuptools_scm"],
    use_scm_version=True,
    packages=["retry_decorator"]
)
