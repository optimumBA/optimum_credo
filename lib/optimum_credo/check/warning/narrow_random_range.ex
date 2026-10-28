defmodule OptimumCredo.Check.Warning.NarrowRandomRange do
  @moduledoc """
  Finds small literal random ranges used in test files, usually to make data "unique".

  Recognised forms (literal integer bounds only, piped or not): `Enum.random(a..b)`,
  `Enum.random(a..b//step)`, `Enum.random(Range.new(a, b))`, `:rand.uniform(n)` and any
  `random_between(a, b)` call (for example `Faker.random_between/2`). Receivers are
  resolved through aliases, so `alias Enum, as: E` works. A range narrower than
  `min_range` (default 1_000_000 values) is reported. Variables, module attributes and
  computed bounds are not evaluated, and picking from a literal list (`Enum.random([:a, :b])`)
  is a choice, not a uniqueness range, so it is not reported. Prefer UUIDs or
  `System.unique_integer/1` for uniqueness.
  """

  use Credo.Check,
    base_priority: :low,
    category: :warning,
    param_defaults: [min_range: 1_000_000],
    explanations: [
      check: """
      A small random range collides sooner or later and causes flaky tests. Use UUIDs, or a
      timestamp plus a large random value, for uniqueness.

      Bad:   Enum.random(1..100)
      Good:  System.unique_integer([:positive])
      """,
      params: [min_range: "Ranges covering fewer values than this are reported."]
    ]

  alias OptimumCredo.TestsSupport

  @doc false
  @spec run(Credo.SourceFile.t(), keyword()) :: [Credo.Issue.t()]
  def run(%Credo.SourceFile{} = source_file, params) do
    if TestsSupport.test_file?(source_file) do
      issue_meta = IssueMeta.for(source_file, params)
      min = Params.get(params, :min_range, __MODULE__)

      source_file
      |> TestsSupport.ast()
      |> TestsSupport.walk_env([], &collect_narrow(&1, &2, &3, min))
      |> Enum.reverse()
      |> Enum.map(fn {label, size, line} ->
        format_issue(issue_meta,
          message:
            "#{label} only yields #{size} distinct values; use a UUID or a much larger range.",
          line_no: line
        )
      end)
    else
      []
    end
  end

  # `1..100 |> Enum.random()`: the piped value is the first argument.
  defp collect_narrow(node, env, acc, min) do
    case size(node, env) do
      {label, size, line} when size < min -> {:cont, [{label, size, line} | acc]}
      _other -> {:cont, acc}
    end
  end

  defp size({:|>, _meta, [left, right]}, env) do
    with %{} = call <- TestsSupport.call(right, env),
         true <- call.args == [] do
      measure(%{call | args: [left]}, env)
    else
      _other -> nil
    end
  end

  defp size(node, env) do
    case TestsSupport.call(node, env) do
      nil -> nil
      call -> measure(call, env)
    end
  end

  defp measure(%{module: "Enum", fun: :random, args: [range]} = call, env) do
    with {:ok, count} <- range_count(range, env), do: {"Enum.random/1", count, line(call)}
  end

  defp measure(%{module: ":rand", fun: :uniform, args: [n]} = call, _env) do
    with {:ok, n} <- int(n), do: {":rand.uniform/1", n, line(call)}
  end

  defp measure(%{fun: :random_between, args: [a, b]} = call, _env) do
    with {:ok, low} <- int(a), {:ok, high} <- int(b) do
      {"random_between/2", abs(high - low) + 1, line(call)}
    end
  end

  defp measure(_call, _env), do: nil

  defp range_count({:.., _meta, [a, b]}, _env), do: count(a, b, 1)

  defp range_count({:..//, _meta, [a, b, step]}, _env) do
    with {:ok, step} <- int(step), do: count(a, b, step)
  end

  defp range_count(node, env) do
    case TestsSupport.call(node, env) do
      %{module: "Range", fun: :new, args: [a, b]} ->
        count(a, b, 1)

      %{module: "Range", fun: :new, args: [a, b, step]} ->
        with {:ok, step} <- int(step), do: count(a, b, step)

      _other ->
        :error
    end
  end

  defp count(a, b, step) do
    with {:ok, low} <- int(a), {:ok, high} <- int(b), true <- step != 0 do
      {:ok, div(abs(high - low), abs(step)) + 1}
    else
      _other -> :error
    end
  end

  defp line(%{meta: meta}), do: meta[:line] || 1

  defp int(n) when is_integer(n), do: {:ok, n}
  defp int({:-, _meta, [n]}) when is_integer(n), do: {:ok, -n}
  defp int({:+, _meta, [n]}) when is_integer(n), do: {:ok, n}
  defp int(_other), do: :error
end
