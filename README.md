# OptimumCredo

Custom Credo checks for Elixir projects to enforce code quality and consistency patterns that reduce manual code review cycles.

## Features

This package provides custom Credo checks to automatically catch common code quality issues:

- **Readability checks** for better code organization and patterns
- **Type safety improvements** for better documentation and maintainability
- **Assertion pattern simplifications** for more idiomatic test code

## Installation

Add the `:optimum_credo` package to your `mix.exs` dependencies:

```elixir
def deps do
  [
    {:optimum_credo, "~> 0.1", only: [:dev, :test], runtime: false},
  ]
end
```

## Usage

Add the checks you want in your `.credo.exs` configuration file:

```elixir
%{
  configs: [
    %{
      name: "default",
      requires: ["./deps/optimum_credo/lib/**/*.ex"],
      checks: [
        # Existing Credo checks...

        # OptimumCredo checks
        {OptimumCredo.Check.Readability.ModuleOrganization, []},
        {OptimumCredo.Check.Readability.DocumentationFormatting, []},
        {OptimumCredo.Check.Readability.UnusedTypes, []},
        {OptimumCredo.Check.Readability.VerboseAssertions, []},
        {OptimumCredo.Check.Readability.ExtractableSpecTypes, []},
        {OptimumCredo.Check.Readability.PrivateFunctionSpecs, []},

        # Original checks
        {OptimumCredo.Check.Readability.DepsOrder, []},
        {OptimumCredo.Check.Readability.ImportOrder, []},
        {OptimumCredo.Check.Readability.TypespecOrder, []},
      ]
    }
  ]
}
```

Then you can run `mix credo` as usual.

## Available Checks

### Readability

#### ModuleOrganization

Enforces blank line separation between different statement types (`use`, `import`, `alias`, `require`).

**Bad:**

```elixir
defmodule MyModule do
  use Supervisor
  import Telemetry.Metrics
  alias MyApp.SomeModule
end
```

**Good:**

```elixir
defmodule MyModule do
  use Supervisor

  import Telemetry.Metrics

  alias MyApp.SomeModule
end
```

#### DocumentationFormatting

Ensures proper spacing in function documentation, specifically blank lines after section headers.

**Bad:**

```elixir
@doc """
Returns the index URL.

## Examples
iex> index_url()
"http://localhost:4000/index.md"
"""
```

**Good:**

```elixir
@doc """
Returns the index URL.

## Examples

iex> index_url()
"http://localhost:4000/index.md"
"""
```

#### UnusedTypes

Detects `@type` definitions that are never used in the module.

**Bad:**

```elixir
@type short_id :: String.t()  # Never used
@type conn :: Plug.Conn.t()

@spec index(conn()) :: conn()
def index(conn), do: conn
```

**Good:**

```elixir
@type conn :: Plug.Conn.t()

@spec index(conn()) :: conn()
def index(conn), do: conn
```

#### VerboseAssertions

Detects verbose assertion patterns that can be simplified to idiomatic Elixir.

**Bad:**

```elixir
assert drop.id != nil
assert user.name == nil
refute item.id != nil
```

**Good:**

```elixir
assert drop.id
refute user.name
refute item.id
```

#### ExtractableSpecTypes

Enforces extraction of common types in `@spec` declarations to semantic module-level type aliases.

**Bad:**

```elixir
@spec show(Plug.Conn.t(), map()) :: Plug.Conn.t()
@spec index(Plug.Conn.t()) :: Plug.Conn.t()
```

**Good:**

```elixir
@type conn :: Plug.Conn.t()
@type params :: map()

@spec show(conn(), params()) :: conn()
@spec index(conn()) :: conn()
```

#### PrivateFunctionSpecs

Detects `@spec` declarations for private functions, which should not have specs.

**Bad:**

```elixir
@spec lookup_cached_entries(list()) :: {:hit, content()} | :miss
defp lookup_cached_entries(ets_match_spec) do
  # ...
end
```

**Good:**

```elixir
defp lookup_cached_entries(ets_match_spec) do
  # ...
end
```

#### DepsOrder (Original)

Enforces alphabetical ordering of dependencies in `app_deps` and `optimum_deps` functions.

#### ImportOrder (Original)

Enforces alphabetical ordering of import statements.

#### TypespecOrder (Original)

Enforces alphabetical ordering of typespec definitions.

## Benefits

1. **Reduces Manual Review Cycles**: Catches trivial formatting issues automatically
2. **Enforces Team Standards**: Consistent code organization across projects
3. **Speeds Up Development**: Less back-and-forth on style issues
4. **Improves Type Safety**: Better documentation and semantic meaning through type aliases

## Testing

Run the test suite:

```bash
mix test
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Add tests for your changes
4. Ensure all tests pass
5. Submit a pull request

## License

This project is licensed under the MIT License.
