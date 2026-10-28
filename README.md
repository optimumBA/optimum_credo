# OptimumCredo

Custom Credo checks for Elixir code-review conventions: module organization,
readability, test design, Phoenix, migrations, configuration and Ash.

Version **0.5.0** moves three previously published checks to KogenCredo. Read
the [migration guide](docs/migration.md) before upgrading.

## Start here

- [Check catalog](docs/checks.md): each detector's behavior, defaults and source.
- [Explicit configuration example](docs/configuration.md): all available checks;
  select the checks and parameters that fit your application.
- [Migration guide](docs/migration.md): checks extracted into KogenCredo.
- [Changelog](CHANGELOG.md): version history and release changes.

## Installation

Add the Hex dependency:

```elixir
{:optimum_credo, "~> 0.5.0", only: [:dev, :test], runtime: false}
```

Requires Credo 1.7.19 or newer in the 1.x series. When adopting this version,
update Credo together with it; an older locked Credo does not provide the token
metadata these checks need, and older releases cannot lint Elixir 1.20 reliably.

For development with a sibling checkout:

```elixir
defp deps do
  [
    {:optimum_credo, path: "../optimum_credo", only: [:dev, :test], runtime: false}
  ]
end
```

Select checks explicitly in `.credo.exs`:

```elixir
%{
  configs: [
    %{
      name: "default",
      checks: %{
        enabled: [
          {OptimumCredo.Check.Readability.ModulePathMismatch, []},
          {OptimumCredo.Check.Readability.SpecWithImpl, []},
          {OptimumCredo.Check.Warning.CallerModuleAttributes,
           [required_prefix: "my_library", allow_attributes: [:public_config]]}
        ]
      }
    }
  ]
}
```

Run `mix credo --strict` to include low-priority advice. Loading the library does
not automatically enable every check. Heuristic findings need review; a warning
is not proof of a bug. Projects can enable OptimumCredo and KogenCredo together;
neither package depends on the other.

## Configuration boundaries

Ordering and naming preferences vary. Configure the relevant parameters rather
than assuming every rule applies to every project. `FunctionOrder` requires an
explicit ordering mode. Domain and namespace checks need application-appropriate
paths and names. Ash checks are intended for applications that use Ash.

`CallerModuleAttributes` is opt-in for macro/DSL library authors. It inspects
literal caller attributes in quoted code and caller-targeted module-attribute
operations. It supports an owner prefix and an allow-list for intentional public
contracts; it does not expand arbitrary macros or prove absence of all collisions.

HEEx detectors inspect `~H` sigils through Credo. Stock Credo excludes standalone
`.heex` files as invalid Elixir, so scan those templates separately:

```sh
mix optimum.heex_check
mix optimum.heex_check lib/ --format json --advisory
```

That command runs the asset-path, hidden-id and event-name checks directly on
raw templates without compiling Phoenix or evaluating template code. Explicit
missing paths, read failures, invalid options and detector errors are errors;
`--advisory` suppresses only the findings exit status. Template findings remain
static hints, not authorization or security proofs.

## Development

```sh
mix deps.get
mix test
mix format --check-formatted
mix compile --warnings-as-errors
mix credo --strict
```

Consumer-derived regression cases include quoted/DSL code, Phoenix contracts,
arity-specific specs and migration nullability replay. `UnusedTypes` defaults to
ignoring the conventional public `t` type (`ignored_types`); schema table checks
can accept their containing context prefix with `allow_context_prefix: true`.
`VerboseAssertions` suggests explicit nil predicates, preserving false-valued
results. `TestNameLowercase` accepts CamelCase identifiers by default through
`allow_camel_case`.

`RequiredFieldConsistency` also recognizes literal context-owned association chains
such as `Comment.changeset(attrs) |> Ecto.Changeset.put_assoc(:user, user)` in the
same project's `lib/` sources. Dynamic dispatch and separated helper calls remain
outside its static scope. `DescribeWithoutErrorCase` accepts a concrete documented
boundary inside one describe via `@describetag error_path_exemption: "reason"`.
Use that only for total operations or to identify separate failure coverage;
missing meaningful failure tests should be added instead.

Folder map: `lib/optimum_credo/check/` owns detectors; other modules under
`lib/optimum_credo/` own shared AST helpers; `test/` owns regression coverage;
`docs/` owns the catalog and migration guide. The root README owns navigation and
development entry points.

## License

MIT. See [LICENSE](LICENSE).
