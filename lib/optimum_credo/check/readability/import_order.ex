defmodule OptimumCredo.Check.Readability.ImportOrder do
  @moduledoc """
  A check that ensures imports are alphabetically ordered.

  Alphabetically ordered imports are more easily scannable by the reader.
  This check enforces that imports are ordered alphabetically within their groups.
  """

  use Credo.Check,
    id: "EX9001",
    base_priority: :low,
    param_defaults: [
      sort_method: :alpha
    ],
    explanations: [
      check: """
      Alphabetically ordered imports are more easily scannable by the reader.

          # preferred

          import ModuleA
          import ModuleB
          import ModuleC

          # NOT preferred

          import ModuleA
          import ModuleC
          import ModuleB

      Imports should be alphabetically ordered among their group:

          # preferred

          import ModuleC
          import ModuleD

          import ModuleA
          import ModuleB

          # NOT preferred

          import ModuleC
          import ModuleD

          import ModuleB
          import ModuleA

      Like all `Readability` issues, this one is not a technical concern.
      But you can improve the odds of others reading and liking your code by making
      it easier to follow.
      """,
      params: [
        sort_method: """
        The ordering method to use.

        Options
        - `:alpha` - Alphabetical case-insensitive sorting.
        - `:ascii` - Case-sensitive sorting where upper case characters are ordered
                      before their lower case equivalent.
        """
      ]
    ]

  alias Credo.Code.Name

  @doc false
  @impl Credo.Check
  def run(%SourceFile{} = source_file, params) do
    sort_method = Params.get(params, :sort_method, __MODULE__)
    issue_meta = IssueMeta.for(source_file, params)

    Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta, sort_method))
  end

  defp traverse({:defmodule, _meta, _args} = ast, issues, issue_meta, sort_method) do
    new_issues =
      ast
      |> extract_import_groups()
      |> Enum.reduce([], &traverse_groups(&1, &2, issue_meta, sort_method))

    {ast, issues ++ new_issues}
  end

  defp traverse(ast, issues, _issue_meta, _sort_method), do: {ast, issues}

  defp traverse_groups(group, acc, issue_meta, sort_method) do
    result =
      group
      |> Enum.chunk_every(2, 1)
      |> Enum.reduce_while(nil, fn chunk, _acc -> process_group(sort_method, chunk) end)

    case result do
      nil -> acc
      line -> [issue_for(issue_meta, line) | acc]
    end
  end

  defp process_group(:alpha, [
         {line_no, mod_list_second, a},
         {_line_no, _mod_list_second, b}
       ])
       when a > b do
    module =
      case mod_list_second do
        {base, _multi_mod_list} -> base
        value -> value
      end

    issue_opts = issue_opts(line_no, module, module)

    {:halt, issue_opts}
  end

  defp process_group(:ascii, [
         {line_no, {a, []}, _compare_name},
         {_line_no, {b, []}, _compare_name2}
       ])
       when a > b do
    {:halt, issue_opts(line_no, a, a)}
  end

  defp process_group(sort_method, [
         {line_no1, mod_list_first, _compare_name1},
         {line_no2, mod_list_second, _compare_name2}
       ]) do
    issue_opts =
      cond do
        issue = inner_group_order_issue(sort_method, line_no1, mod_list_first) ->
          issue

        issue = inner_group_order_issue(sort_method, line_no2, mod_list_second) ->
          issue

        true ->
          nil
      end

    if issue_opts do
      {:halt, issue_opts}
    else
      {:cont, nil}
    end
  end

  defp process_group(sort_method, [{line_no1, mod_list_first, _compare_name}]) do
    if issue_opts = inner_group_order_issue(sort_method, line_no1, mod_list_first) do
      {:halt, issue_opts}
    else
      {:cont, nil}
    end
  end

  defp process_group(_sort_method, _chunk), do: {:cont, nil}

  defp inner_group_order_issue(_sort_method, _line_no, {_base, []}), do: nil

  defp inner_group_order_issue(:ascii = _sort_method, line_no, {base, mod_list}) do
    sorted_mod_list = Enum.sort(mod_list)

    if mod_list != sorted_mod_list do
      issue_opts(line_no, base, mod_list, mod_list, sorted_mod_list)
    end
  end

  defp inner_group_order_issue(_sort_method, line_no, {base, mod_list}) do
    downcased_mod_list = Enum.map(mod_list, &String.downcase(to_string(&1)))
    sorted_downcased_mod_list = Enum.sort(downcased_mod_list)

    if downcased_mod_list != sorted_downcased_mod_list do
      issue_opts(line_no, base, mod_list, downcased_mod_list, sorted_downcased_mod_list)
    end
  end

  defp issue_opts(line_no, base, mod_list, comparison_mod_list, sorted_comparison_mod_list) do
    trigger =
      comparison_mod_list
      |> Enum.with_index()
      |> Enum.find_value(fn {comparison_mod_entry, index} ->
        if comparison_mod_entry != Enum.at(sorted_comparison_mod_list, index) do
          Enum.at(mod_list, index)
        end
      end)

    issue_opts(line_no, [base, trigger], trigger)
  end

  defp issue_opts(line_no, module, trigger) do
    %{
      line_no: line_no,
      trigger: trigger,
      module: module
    }
  end

  defp extract_import_groups({:defmodule, _meta, _args} = ast) do
    groups =
      ast
      |> Credo.Code.postwalk(&find_import_groups/2)
      |> Enum.reverse()

    result =
      Enum.reduce(groups, [[]], fn
        nil, [[] | rest] -> [[]] ++ rest
        nil, acc -> [[]] ++ acc
        definition, [group | groups] -> [[definition | group] | groups]
      end)

    result
    |> Enum.map(&Enum.reverse/1)
    |> Enum.reverse()
  end

  defp find_import_groups(
         {:import, _meta, [{:__aliases__, meta, mod_list} | _rest]} = ast,
         imports
       ) do
    compare_name = compare_name(ast)
    modules = [{meta[:line], {Name.full(mod_list), []}, compare_name}]

    accumulate_import_into_group(ast, modules, meta[:line], imports)
  end

  defp find_import_groups(ast, imports), do: {ast, imports}

  defp compare_name(value) do
    value
    |> Macro.to_string()
    |> String.downcase()
    |> String.replace(~r/[\{\}]/, "")
    |> String.replace(~r/,.+/, "")
  end

  defp accumulate_import_into_group(
         ast,
         modules,
         line,
         [{line_no, _mod, _compare} | _rest] = imports
       )
       when line_no != 0 and line_no != line - 1 do
    {ast, modules ++ [nil] ++ imports}
  end

  defp accumulate_import_into_group(ast, modules, _line, imports) do
    {ast, modules ++ imports}
  end

  defp issue_for(issue_meta, %{line_no: line_no, trigger: trigger, module: module}) do
    format_issue(
      issue_meta,
      message: "The import `#{Name.full(module)}` is not alphabetically ordered among its group.",
      trigger: trigger,
      line_no: line_no
    )
  end
end
