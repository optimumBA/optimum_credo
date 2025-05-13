# optimum_credo

## Installation

Add the `:optimum_credo` package to your `mix.exs` dependencies:

```elixir
def deps do
  [
    {:optimum_credo, "~> 0.1", only: :test, runtime: false},
  ]
end
```

## Usage

Add the checks you want in your `.credo.exs` configuration file.

For example:

```elixir
{OptimumCredo.Check.Readability.ImportOrder, []},
```

Then you can run `mix credo` per usual.

### Available rules

```elixir
OptimumCredo.Check.Readability.DepsOrder
OptimumCredo.Check.Readability.ImportOrder
OptimumCredo.Check.Readability.TypespecOrder
```
