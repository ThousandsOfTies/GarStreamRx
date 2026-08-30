# Gapless Agent Runtime build environment.

PRODUCT_BUILD_SCRIPT ?= scripts/product-build.sh
PRODUCT_ARTIFACTS_SCRIPT ?= scripts/product-artifacts.sh
PRODUCT_CLEAN_SCRIPT ?= scripts/product-clean.sh

ARTIFACT_ROOT ?= artifacts/from-codespace
DEPLOYMENT ?= luckfox-rk3506

.PHONY: all setup sync build artifacts clean check-deployment

all: artifacts

setup:
	scripts/setup-product-branch.sh

sync:
	@if [ -f .gitmodules ]; then \
		git submodule foreach --recursive 'branch=$$(git branch --show-current); if [ -n "$$branch" ]; then git pull --ff-only; else echo "detached HEAD; skip pull"; fi'; \
	fi

build:
	@if [ -x "$(PRODUCT_BUILD_SCRIPT)" ]; then \
		"$(PRODUCT_BUILD_SCRIPT)"; \
	else \
		echo "No product build script: $(PRODUCT_BUILD_SCRIPT)"; \
	fi

artifacts: build
	@if [ -x "$(PRODUCT_ARTIFACTS_SCRIPT)" ]; then \
		"$(PRODUCT_ARTIFACTS_SCRIPT)" "$(ARTIFACT_ROOT)"; \
	else \
		echo "No product artifacts script: $(PRODUCT_ARTIFACTS_SCRIPT)"; \
	fi

clean:
	@if [ -x "$(PRODUCT_CLEAN_SCRIPT)" ]; then \
		"$(PRODUCT_CLEAN_SCRIPT)"; \
	fi
	rm -rf "$(ARTIFACT_ROOT)"

check-deployment:
	scripts/package-target.sh --deployment "$(DEPLOYMENT)" --describe >/dev/null
	PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests -p 'test_deployment_profiles.py' -v
