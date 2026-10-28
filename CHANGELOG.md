# Changelog

## Unreleased

- Added the complete review-derived check collection: 74 checks for readability, module organization, tests, Phoenix, configuration, migrations and optional Ash policies. See `docs/checks.md` for behavior and parameters.
- Added `mix optimum.heex_check` to scan standalone HEEx templates and the opt-in `CallerModuleAttributes` check for macro and DSL libraries.
- Fixed false positives in types and specs, quoted and DSL code, Phoenix callbacks, schema migration replay, dependency requirements, Ecto lock clauses, test naming and paths. Added context-owned association recognition and documented describe-level error-path exemptions.
- Kept source-derived identities as strings instead of allocating atoms; inspected installed BEAM metadata without loading modules and supported long paths on older OTP versions.
- Fixed Credo JSON diagnostics and Elixir 1.20 compatibility. Require Credo 1.7.19 or newer within 1.x.
- **BREAKING:** Moved `EmptySetupBlock`, `RuntimeEnvDevDefault` and `SkippedTest` from OptimumCredo to KogenCredo. The previously unreleased `JustifiedCoverageIgnore` also belongs to KogenCredo. Add KogenCredo and update enabled module names as described in `docs/migration.md`; old names no longer run.

## 0.4.0 (2026-04-29)

- Added `SkippedTest` warning check to detect `@tag :skip`, `@tag skip: true`, and `@moduletag :skip` annotations that hide failing tests. Supports an `allow_with_comment` param to exempt tags annotated with an inline explanation.
- Added `EmptySetupBlock` readability check to detect `setup do :ok end`, `setup do end`, and `setup do {:ok, %{}} end` blocks in test files that provide no value and should be removed.
- Added `RuntimeEnvDevDefault` warning check to detect `System.get_env/2` calls in `config/runtime.exs` that use a developer-machine path (`/Users/`, `/home/`, `~/`) as the default value.
- Added `CaseTrueFalse` refactor check to detect `case` expressions with exactly two clauses matching literal `true` and `false`, suggesting replacement with an `if` expression.

## 0.3.0 (2026-03-31)

- Added `LiveViewBareMatch` check to catch bare `{:ok, _} =` and `{:error, _} =` pattern matches in LiveView modules, preventing silent process crashes on failed Ecto operations.

## 0.2.0 (2026-03-13)

- Added 6 new readability checks: `DocumentationFormatting`, `ExtractableSpecTypes`, `ModuleOrganization`, `PrivateFunctionSpecs`, `UnusedTypes`, and `VerboseAssertions`.
- Fixed Elixir 1.19 compatibility by upgrading Credo to 1.7.17.

## 0.1.0 (2025-05-13)

Initial release
