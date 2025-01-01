# Overridable vars
PYTHON_VERSION ?= 3.11
PBR_VERSION ?= 1.0.0

# Functional vars
BASE_IMAGE_NAME := retry-decorator
PACKAGE_NAME := python-$(BASE_IMAGE_NAME)
SOURCE_DIR := retry_decorator
PIP_TOOLS_IMAGE := $(BASE_IMAGE_NAME)-piptools
BUILDER_IMAGE := $(BASE_IMAGE_NAME)-builder
PYTHON_CODE_FILES := $(shell find $(CURDIR)/$(SOURCE_DIR) -type f -name "*.py")
SHELL := /bin/bash -o pipefail

# Dockerizable tools
DOCKER_RUN = docker run --rm -t -e PBR_VERSION=$(PBR_VERSION) -v $(CURDIR):/workspace -v $(CURDIR)/.git:/workspace/.git -w /workspace
DOCKER_BUILD = docker build --build-arg PYTHON_VERSION=$(PYTHON_VERSION)
PYTHON = $(DOCKER_RUN) $(BUILDER_IMAGE) python
TOX = $(DOCKER_RUN) $(BUILDER_IMAGE) tox
PIP_COMPILE = $(DOCKER_RUN) $(PIP_TOOLS_IMAGE) pip-compile
ISORT = $(DOCKER_RUN) $(BUILDER_IMAGE) isort

# Meta targets
.DEFAULT_GOAL := help

.PHONY: all
all: lint test dist  ## Perform: lint, test, dist

.PHONY: help
help: ## Display this help message
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[93m<target>\033[0m\n\nTargets:\n"} \
		/^[a-zA-Z_-]+:.*?##/ { printf "  \033[93m%-14s\033[0m\t%s\n", $$1, $$2 }' \
	   	$(MAKEFILE_LIST)

FORCE: ;

.PHONY: build-docker main-docker
build-docker: main-docker
main-docker: .cache/main-docker.stamp  ## Build main docker image

.cache/main-docker.stamp: docker/Dockerfile.main
	mkdir -p $$(dirname $@)
	$(DOCKER_BUILD) --file $< --tag $(BUILDER_IMAGE) .
	touch $@

.PHONY: dist
dist: artifacts/$(PACKAGE_NAME)-$(PBR_VERSION).tar.gz  ## Build python package

artifacts/$(PACKAGE_NAME)-$(PBR_VERSION).tar.gz: .cache/main-docker.stamp $(PYTHON_CODE_FILES)
	mkdir -p "artifacts"
	$(PYTHON) setup.py check --metadata --restructuredtext --strict
	$(PYTHON) setup.py sdist --dist-dir "./artifacts/"

.PHONY: installcheck
installcheck: artifacts/$(PACKAGE_NAME)-$(PBR_VERSION).tar.gz  ## Test pip package validity
	$(DOCKER_RUN) $(BUILDER_IMAGE) python -m pip install $<

.PHONY: shell
shell: build-docker  ## Interactive shell
	$(DOCKER_RUN) --interactive $(BUILDER_IMAGE) /bin/bash

.PHONY: lint
lint: artifacts/lint.log  ## Linting

artifacts/lint.log: .cache/main-docker.stamp $(PYTHON_CODE_FILES) FORCE
	mkdir -p "artifacts"
	$(PYTHON) -m flake8 --statistics setup.py tests/ $(SOURCE_DIR)/ | tee $@
	$(PYTHON) -m mypy --ignore-missing-imports --package $(SOURCE_DIR) --no-error-summary | tee -a $@
	$(PYTHON) -m pydocstyle $(SOURCE_DIR) | tee -a $@
	$(ISORT) $(SOURCE_DIR) --settings-file tox.ini --dont-follow-links --diff | tee -a $@
	# Successfully linted.

.PHONY: fmt
fmt: .cache/main-docker.stamp ## Format python imports
	$(ISORT) $(SOURCE_DIR) --settings-file tox.ini --dont-follow-links --no-inline-sort --atomic

.PHONY: reqs
reqs: requirements.txt tests/requirements.txt  ## Update requirements via pip-compile

requirements.txt: requirements.in FORCE | .cache/piptools-docker.stamp
	$(PIP_COMPILE) --upgrade --output-file $@ $<

tests/requirements.txt: tests/requirements.in FORCE | .cache/piptools-docker.stamp
	$(PIP_COMPILE) --upgrade --output-file $@ $<

.cache/piptools-docker.stamp: docker/Dockerfile.piptools
	mkdir -p $$(dirname $@)
	$(DOCKER_BUILD) --file $< --tag $(PIP_TOOLS_IMAGE) .
	touch $@

.PHONY: test
test: build-docker  ## Run tests
	$(TOX)

.PHONY: clean
clean: testclean distclean  ## Clean various files
	find $(CURDIR) -type f -name '*.pyc' -delete
	find $(CURDIR) -type d -name '__pycache__' -exec rm -r {} +
	find $(CURDIR) -type d -name '.mypy_cache' -exec rm -r {} +
	find $(CURDIR) -type d -name '.cache' -exec rm -r {} +

.PHONY: distclean
distclean:  ## Clean dist files
	find $(CURDIR) -type d -name '.eggs' -exec rm -r {} +
	find $(CURDIR) -type d -name '*.egg-info' -exec rm -r {} +
	find $(CURDIR) -type d -name 'artifacts' -exec rm -r {} +
	find $(CURDIR) -type f -name '.docker-stamp' -delete

.PHONY: testclean
testclean:  ## Clean files created during tox
	find $(CURDIR) -type f -name '.coverage' -delete
	find $(CURDIR) -type d -name '.tox' -exec rm -r {} +
	find $(CURDIR) -type d -name '.pytest_cache' -exec rm -r {} +
