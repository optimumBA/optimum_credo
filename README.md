# optimum_credo

## Installation

Add the `:optimum_credo` package to your `mix.exs` dependencies:

```elixir
def deps do
  [
    {:optimum_credo, "~> 1.0", only: [:dev, :test], runtime: false}
  ]
end
```

## Usage

You just need to add the checks you want in your `.credo.exs` configuration file.

For example:
```elixir
{OptimumCredo.OptimumCredo.Check.Readability.ImportOrder}
```


