defmodule OptimumCredo.Check.Warning.HardcodedYearInTest do
  @moduledoc """
  Finds hardcoded calendar years in test date construction, for years within
  `min_year..max_year` (default 2020..2100).

  Reported forms, each with the line of the literal itself:

    * `~D`/`~N`/`~U` sigils starting with a year
    * ISO date or datetime strings (`"2025-01-31"`, `"2025-01-31T10:00:00Z"`, and
      interpolated prefixes such as `"2025-01-\#{day}"`) with a valid month and day
    * the year argument of `Date.new/new!` and `NaiveDateTime.new/new!`, and the year of a
      literal tuple passed to `Date`/`NaiveDateTime`/`DateTime` `from_erl/from_erl!`
    * `year: 2025` only inside a map, struct or keyword list that also has `month:` or
      `day:` (date construction such as `%Date{year: .., month: ..}`)

  Other integers are never reported: `500`, `2024` as a price or id, or `year: 2021` on a
  book fixture. Calls are resolved through aliases. Heuristic: dates fixed deliberately in
  the past are also reported, and dates built from variables or module attributes
  (`@year 2025`) are invisible.
  """

  use Credo.Check,
    base_priority: :low,
    category: :warning,
    param_defaults: [min_year: 2020, max_year: 2100, allow_years: []],
    explanations: [
      check: """
      A fixed year can make a time-relative test expire. Derive time-relative dates from
      `Date.utc_today/0` or use an explicit frozen clock. Fixed historical fixtures are
      legitimate; configure `allow_years` for those intentional cases.

      Bad:   Date.new!(2025, 1, 31)
      Good:  Date.add(Date.utc_today(), 30)
      """,
      params: [
        min_year: "Smallest year reported.",
        max_year: "Largest year reported.",
        allow_years: "Years that are always accepted."
      ]
    ]

  alias OptimumCredo.TestsSupport

  @sigils [:sigil_D, :sigil_N, :sigil_U]
  @date_modules ["Date", "NaiveDateTime"]
  @erl_modules ["Date", "NaiveDateTime", "DateTime"]
  @doc_attributes [:doc, :moduledoc, :typedoc]

  @doc false
  @spec run(Credo.SourceFile.t(), keyword()) :: [Credo.Issue.t()]
  def run(%Credo.SourceFile{} = source_file, params) do
    ast = if TestsSupport.test_file?(source_file), do: TestsSupport.literal_ast(source_file)

    if ast do
      issue_meta = IssueMeta.for(source_file, params)
      min = Params.get(params, :min_year, __MODULE__)
      max = Params.get(params, :max_year, __MODULE__)
      allow = Params.get(params, :allow_years, __MODULE__)
      in_range? = fn year -> year >= min and year <= max and year not in allow end

      ast
      |> TestsSupport.walk_env([], fn node, env, acc -> visit(node, env, acc) end)
      |> Enum.filter(fn {year, _line} -> in_range?.(year) end)
      |> Enum.reverse()
      |> Enum.map(fn {year, line} ->
        format_issue(issue_meta,
          message:
            "Fixed year #{year}; check whether this test depends on today. Derive time-relative dates, or explicitly allow a fixed historical fixture.",
          line_no: line,
          trigger: to_string(year)
        )
      end)
    else
      []
    end
  end

  defp visit({:@, _meta, [{attribute, _tuple_meta, _args}]}, _env, acc)
       when attribute in @doc_attributes,
       do: {:skip, acc}

  defp visit({sigil, meta, [{:<<>>, _meta, [text | _tail]}, _second]}, _env, acc)
       when sigil in @sigils and is_binary(text),
       do: {:skip, add(acc, iso_year(text), meta[:line])}

  # Interpolated strings: only the leading literal part can start with a date.
  defp visit({:<<>>, meta, [text | _tail]}, _env, acc) when is_binary(text),
    do: {:cont, add(acc, iso_year(text, true), meta[:line])}

  defp visit({:__block__, meta, [text]}, _env, acc) when is_binary(text),
    do: {:skip, add(acc, iso_year(text), meta[:line])}

  # Raw binaries only remain as parts of an interpolated string (handled above).
  defp visit(text, _env, acc) when is_binary(text), do: {:skip, acc}

  defp visit({:%{}, _meta, pairs}, _env, acc) when is_list(pairs),
    do: {:cont, date_fields(pairs, acc)}

  defp visit(list, _env, acc) when is_list(list) do
    if list != [] and Enum.all?(list, &match?({_, _}, &1)),
      do: {:cont, date_fields(list, acc)},
      else: {:cont, acc}
  end

  defp visit(node, env, acc) do
    case TestsSupport.call(node, env) do
      %{kind: :remote, module: module, fun: fun, args: [first | _tail]} ->
        {:cont, call_year(module, fun, first, acc)}

      _other ->
        {:cont, acc}
    end
  end

  defp call_year(module, fun, first, acc) when module in @date_modules and fun in [:new, :new!],
    do: add_literal(acc, first)

  defp call_year(module, fun, first, acc)
       when module in @erl_modules and fun in [:from_erl, :from_erl!],
       do: add_literal(acc, erl_year(first))

  defp call_year(_module, _fun, _first, acc), do: acc

  defp erl_year({:__block__, _meta, [tuple]}), do: erl_year(tuple)
  defp erl_year({:{}, _meta, [year | _tail]}), do: year
  defp erl_year({{:__block__, _meta, [{:{}, _tuple_meta, [year | _tail]}]}, _time}), do: year
  defp erl_year({date, _time}), do: erl_year(date)
  defp erl_year(_other), do: nil

  defp date_fields(pairs, acc) do
    keys = for {key, _value} <- pairs, {:ok, atom, _args} <- [TestsSupport.literal(key)], do: atom

    if :year in keys and (:month in keys or :day in keys) do
      Enum.reduce(pairs, acc, &add_year_field/2)
    else
      acc
    end
  end

  defp add_year_field({key, value}, acc) do
    if match?({:ok, :year, _}, TestsSupport.literal(key)),
      do: add_literal(acc, value),
      else: acc
  end

  defp add_year_field(_other, acc), do: acc

  defp add_literal(acc, node) do
    case TestsSupport.literal(node) do
      {:ok, year, line} when is_integer(year) -> [{year, line || 1} | acc]
      _other -> acc
    end
  end

  defp add(acc, nil, _line), do: acc
  defp add(acc, year, line), do: [{year, line || 1} | acc]

  defp iso_year(text, partial? \\ false) do
    pattern =
      if partial?,
        do: ~r/^(\d{4})-(0[1-9]|1[0-2])(-|$)/,
        else: ~r/^(\d{4})-(0[1-9]|1[0-2])-(0[1-9]|[12]\d|3[01])(?!\d)/

    case Regex.run(pattern, text) do
      [_first, year | _tail] -> String.to_integer(year)
      _other -> nil
    end
  end
end
