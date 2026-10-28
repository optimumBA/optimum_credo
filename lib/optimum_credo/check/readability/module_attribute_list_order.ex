defmodule OptimumCredo.Check.Readability.ModuleAttributeListOrder do
  @moduledoc """
  Finds module attributes holding literal atom or string lists in non-alphabetical order.

  Reads `@name [:b, :a, :c]` and `@name ~w(b a c)` / `~w(b a c)a`. The list must
  contain only atoms or only strings and have at least `min_run` entries. Built-in
  attributes such as `@doc`, `@spec`, and `@derive` are not inspected.

  This is a static heuristic: it cannot know when order carries meaning (stages,
  priorities, fallbacks), so list those attributes in `ignore_attributes`. Keyword
  lists, lists with non-literal elements, and values behind function calls are
  skipped.

  ## Parameters

  - `min_run`: minimum list length to check (default `3`).
  - `ignore_attributes`: attribute names (atoms or strings) whose order is meaningful.
  """

  use Credo.Check,
    base_priority: :low,
    category: :readability,
    param_defaults: [min_run: 3, ignore_attributes: []],
    explanations: [
      check: """
      Keep literal lists in module attributes alphabetical.

      ## Bad

      ```elixir
      @roles [:member, :admin, :guest]
      ```

      ## Good

      ```elixir
      @roles [:admin, :guest, :member]
      ```

      Use `ignore_attributes` for lists where order is semantic, such as `@stages`.
      """,
      params: [
        min_run: "Minimum list length that is checked.",
        ignore_attributes: "Attributes whose order is meaningful."
      ]
    ]

  alias OptimumCredo.OptimumStructureSupport

  @builtin ~w(doc moduledoc typedoc spec type typep opaque callback macrocallback impl
              behaviour derive dialyzer compile deprecated on_load vsn optional_callbacks)a

  @doc false
  @spec run(Credo.SourceFile.t(), keyword()) :: [Credo.Issue.t()]
  def run(%Credo.SourceFile{} = source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)
    min_run = Params.get(params, :min_run, __MODULE__)

    ignored =
      params
      |> Params.get(:ignore_attributes, __MODULE__)
      |> OptimumStructureSupport.to_strings()

    source_file
    |> Credo.Code.prewalk(fn
      {:@, meta, [{name, _meta, [value]}]} = ast, issues
      when is_atom(name) and name not in @builtin ->
        {ast, check(name, value, meta, ignored, min_run, issue_meta) ++ issues}

      ast, issues ->
        {ast, issues}
    end)
    |> Enum.reverse()
  end

  defp check(name, value, meta, ignored, min_run, issue_meta) do
    with false <- Atom.to_string(name) in ignored,
         names when is_list(names) and length(names) >= min_run <- literal_list(value),
         {previous, current, _line} <- OptimumStructureSupport.first_unsorted(names) do
      [
        format_issue(issue_meta,
          message: "Put #{current} before #{previous} in @#{name} to keep the list alphabetical.",
          line_no: meta[:line] || 1
        )
      ]
    else
      _other -> []
    end
  end

  defp literal_list(list) when is_list(list) do
    with names when is_list(names) <- OptimumStructureSupport.literal_names(list),
         do: Enum.map(names, fn {n, _value} -> {n, 0} end)
  end

  defp literal_list({:sigil_w, _meta, [{:<<>>, _meta2, [words]}, modifiers]})
       when is_binary(words) do
    words
    |> String.split()
    |> Enum.map(&{&1, 0})
    |> then(&if(modifiers in [[], ~c"a", ~c"c", ~c"s"], do: &1))
  end

  defp literal_list(_value), do: nil
end
