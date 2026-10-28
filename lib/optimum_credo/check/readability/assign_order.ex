defmodule OptimumCredo.Check.Readability.AssignOrder do
  @moduledoc """
  Finds chained or literal `assign` keys that are not in alphabetical order.

  Three literal forms are inspected:

  - a pipeline of `assign(:key, value)` calls (`socket |> assign(:b, 1) |> assign(:a, 2)`),
  - a call with keyword keys, `assign(socket, b: 1, a: 2)`,
  - a call with a literal map, `assign(socket, %{b: 1, a: 2})`.

  Consecutive `assign` stages in one pipeline form a single chain. Any other stage,
  or an `assign` with a dynamic key or variable map, ends the chain. Keys listed in
  `pinned_assigns` must come first (in the configured order); the remaining keys are
  compared alphabetically.

  This is a static heuristic: any local or `Phoenix.Component` call named `assign`
  is treated as LiveView's, and separate statements (`socket = assign(...)`) are not
  joined into a chain.

  ## Parameters

  - `min_run`: minimum number of keys in a chain (default `3`).
  - `pinned_assigns`: keys that stay first, such as `[:module]`.
  """

  use Credo.Check,
    base_priority: :low,
    category: :readability,
    param_defaults: [min_run: 3, pinned_assigns: [:module]],
    explanations: [
      check: """
      Keep chained assigns in alphabetical order, with pinned keys such as `:module`
      first.

      ## Bad

      ```elixir
      socket
      |> assign(:title, "Hi")
      |> assign(:module, __MODULE__)
      |> assign(:count, 0)
      ```

      ## Good

      ```elixir
      socket
      |> assign(:module, __MODULE__)
      |> assign(:count, 0)
      |> assign(:title, "Hi")
      ```

      Chains shorter than `min_run` keys are ignored.
      """,
      params: [
        min_run: "Minimum number of keys in a chain.",
        pinned_assigns: "Keys that must stay first."
      ]
    ]

  alias OptimumCredo.OptimumStructureSupport

  @doc false
  @spec run(Credo.SourceFile.t(), keyword()) :: [Credo.Issue.t()]
  def run(%Credo.SourceFile{} = source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)
    min_run = Params.get(params, :min_run, __MODULE__)

    pinned =
      params
      |> Params.get(:pinned_assigns, __MODULE__)
      |> OptimumStructureSupport.to_strings()

    source_file
    |> Credo.SourceFile.ast()
    |> chains()
    |> Enum.filter(&(length(&1) >= min_run))
    |> Enum.flat_map(fn chain ->
      chain
      |> Enum.map(fn {key, line} -> {sort_key(key, pinned), line} end)
      |> OptimumStructureSupport.first_unsorted()
      |> unsorted_issues(issue_meta)
    end)
  end

  defp unsorted_issues({_previous, {_group, _index, key}, line}, issue_meta) do
    [
      format_issue(issue_meta,
        message: "Reorder the assign for #{key}: pinned keys first, the rest alphabetical.",
        line_no: line
      )
    ]
  end

  defp unsorted_issues(nil, _issue_meta), do: []

  defp sort_key(key, pinned) do
    case Enum.find_index(pinned, &(&1 == key)) do
      nil -> {1, 0, key}
      index -> {0, index, key}
    end
  end

  # Collects chains (lists of {key, line}) from the whole AST.
  defp chains({:|>, _meta, _args} = pipeline) do
    stages = flatten(pipeline)
    {done, current} = Enum.reduce(stages, {[], []}, &fold_stage/2)

    nested =
      stages
      |> Enum.flat_map(&stage_arguments/1)
      |> Enum.flat_map(&chains/1)

    Enum.reverse([Enum.reverse(current) | done]) ++ nested
  end

  defp chains({:assign, meta, [_socket | rest]} = call) do
    keys = assign_keys(rest, meta[:line] || 1)
    if keys, do: [keys | nested_chains(call)], else: nested_chains(call)
  end

  defp chains(term) when is_tuple(term), do: nested_chains(term)
  defp chains(list) when is_list(list), do: Enum.flat_map(list, &chains/1)
  defp chains(_term), do: []

  defp nested_chains(term) do
    term
    |> Tuple.to_list()
    |> Enum.flat_map(&chains/1)
  end

  defp flatten({:|>, _meta, [left, right]}) do
    stages = flatten(left)
    Enum.concat(stages, [right])
  end

  defp flatten(head), do: [{:head, head}]

  defp fold_stage({:head, {:assign, meta, [_socket | rest]}}, {done, current}) do
    rest
    |> assign_keys(meta[:line] || 1)
    |> extend(done, current)
  end

  defp fold_stage({:assign, meta, args}, {done, current}) when is_list(args) do
    args
    |> assign_keys(meta[:line] || 1)
    |> extend(done, current)
  end

  defp fold_stage(_other, {done, current}), do: {[Enum.reverse(current) | done], []}

  defp extend(nil, done, current), do: {[Enum.reverse(current) | done], []}
  defp extend(keys, done, current), do: {done, Enum.reverse(keys, current)}

  # Arguments of each stage, searched for nested pipelines inside values.
  defp stage_arguments({:head, {_name, _meta, args}}) when is_list(args), do: args
  defp stage_arguments({:head, other}), do: [other]
  defp stage_arguments({_name, _meta, args}) when is_list(args), do: args
  defp stage_arguments(_stage), do: []

  defp assign_keys([key, _value | _rest], line) when is_atom(key) and not is_nil(key),
    do: [{Atom.to_string(key), line}]

  defp assign_keys([[_head | _tail] = keyword], line), do: literal_pairs(keyword, line)
  defp assign_keys([{:%{}, _meta, [_head | _tail] = pairs}], line), do: literal_pairs(pairs, line)
  defp assign_keys(_args, _line), do: nil

  defp literal_pairs(pairs, line) do
    if Enum.all?(pairs, &match?({key, _value} when is_atom(key), &1)) do
      Enum.map(pairs, fn {key, _value} -> {Atom.to_string(key), line} end)
    end
  end
end
