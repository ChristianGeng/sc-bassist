.PHONY: help install-sc run live test lint

help:
	@echo "make install-sc  install SuperCollider without root (~/.local/opt/supercollider)"
	@echo "make run         start with the demo groove"
	@echo "make live        start on the audio input (then: scripts/route-app.sh firefox)"
	@echo "make test        compile, unit, ui and integration tests (silent)"
	@echo "make lint        shellcheck"

install-sc:
	scripts/install-local-sc.sh

run:
	./run.sh

live:
	./run.sh --live

test:
	scripts/test.sh

lint:
	shellcheck run.sh scripts/*.sh
