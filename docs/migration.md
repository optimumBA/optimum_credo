# KogenCredo 0.1.0 / OptimumCredo 0.5.0 migration

OptimumCredo owns code-review conventions. KogenCredo owns generated-code failure
patterns and test-gate integrity. The libraries are independent Credo dependencies.
This guide describes the coordinated configuration migration.

The following checks are moved with their tests and original copyright notice:

| Previous module | New module |
| --- | --- |
| `OptimumCredo.Check.Readability.EmptySetupBlock` | `KogenCredo.Check.Readability.EmptySetupBlock` |
| `OptimumCredo.Check.Warning.RuntimeEnvDevDefault` | `KogenCredo.Check.Warning.RuntimeEnvDevDefault` |
| `OptimumCredo.Check.Warning.SkippedTest` | `KogenCredo.Check.Warning.SkippedTest` |
| Unreleased `OptimumCredo.Check.Readability.JustifiedCoverageIgnore` | `KogenCredo.Check.Readability.JustifiedCoverageIgnore` |

Both libraries require Credo 1.7.19 or newer in the 1.x series; update the
consumer's locked Credo together with the library.

Add KogenCredo as a separate dependency and change the enabled module names in
`.credo.exs`. Use:

```elixir
{:kogen_credo, "~> 0.1.0", only: [:dev, :test], runtime: false}
```

**BREAKING configuration change:** Credo ignores an undefined check with a warning
and can still exit successfully. Leaving the old module names in `.credo.exs`
after upgrading therefore silently removes those gates; a green command is not
proof that the moved checks ran. Enable the new Kogen names and verify they are
selected. KogenCredo must be publicly installable before the Optimum extraction
is published.

The first three old names exist in published OptimumCredo 0.4.0 but are absent from
the 0.5.0 split. `JustifiedCoverageIgnore` was never part of that release.
OptimumCredo 0.5.0 removes those published module names; this is a breaking
configuration change. Existing applications should keep their released pins until
the coordinated migration is ready; do not switch production dependencies to this
working tree merely because local qualification passed.

Review overlapping detectors when selecting both libraries. For example,
OptimumCredo's test-convention checks and KogenCredo's configurable forbidden calls
can intentionally report the same sleep. Enable the policy that matches your
application rather than enabling every overlapping detector twice.
