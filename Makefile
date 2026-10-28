.PHONY: ci

ci:
	mix format --check-formatted
	mix compile --warnings-as-errors
	mix test
	mix credo --strict
	mix docs --warnings-as-errors
