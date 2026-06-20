# SAM custom build: assemble the Lambda artifact from the handler plus the
# shared rpgme package (kept single-sourced at the repo root, not duplicated).
# boto3 is provided by the Lambda runtime, so there are no third-party deps to
# pip install — the engine itself is pure standard library.

build-RpgMeFunction:
	mkdir -p "$(ARTIFACTS_DIR)"
	cp handler.py "$(ARTIFACTS_DIR)/"
	cp -r ../rpgme "$(ARTIFACTS_DIR)/rpgme"
	find "$(ARTIFACTS_DIR)/rpgme" -name '__pycache__' -type d -prune -exec rm -rf {} +
