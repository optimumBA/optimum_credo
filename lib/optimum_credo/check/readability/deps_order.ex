defmodule OptimumCredo.Check.Readability.DepsOrder do
  @moduledoc """
  A check that ensures dependencies are alphabetically ordered within their groups.

  Alphabetically ordered dependencies are more easily scannable by the reader.
  This check enforces that dependencies in app_deps and optimum_deps
  are ordered alphabetically within their respective groups.
  """

  use Credo.Check,
    id: "EX9002",
    base_priority: :low,
    param_defaults: [
      sort_method: :alpha
    ],
    explanations: [
      check: """
      Alphabetically ordered dependencies are more easily scannable by the reader.

          # preferred

          defp app_deps do
            [
              {:bcrypt_elixir, "~> 3.0"},
              {:mdex, "~> 0.4.0"},
              {:multipart, "~> 0.4"},
              {:number, "~> 1.0"},
              {:plug, "~> 1.14"}
            ]
          end

          # NOT preferred

          defp app_deps do
            [
              {:bcrypt_elixir, "~> 3.0"},
              {:multipart, "~> 0.4"},
              {:number, "~> 1.0"},
              {:plug, "~> 1.14"},
              {:mdex, "~> 0.4.0"}
            ]
          end

      Dependencies should be alphabetically ordered within each deps group:
      - app_deps
      - optimum_deps

      Like all `Readability` issues, this one is not a technical concern.
      But you can improve the odds of others reading and liking your code by making
      it easier to follow.
      """,
      params: [
        sort_method: """
        The ordering method to use.

        Options
        - `:alpha` - Alphabetical case-insensitive sorting.
        """
      ]
    ]

  @doc false
  @impl Credo.Check
  def run(%SourceFile{} = source_file, params) do
    sort_method = Params.get(params, :sort_method, __MODULE__)
    issue_meta = IssueMeta.for(source_file, params)

    source_file
    |> Credo.Code.ast()
    |> find_deps_functions()
    |> Enum.flat_map(fn deps_function ->
      check_deps_order(deps_function, issue_meta, sort_method)
    end)
  end

  defp find_deps_functions(ast) do
    {_ast, deps_functions} =
      Macro.prewalk(ast, [], fn
        {:defp, _meta, [{name, _fun_meta, _args}, _do_block]} = node, acc
        when name in [:app_deps, :optimum_deps] ->
          {node, [node | acc]}

        node, acc ->
          {node, acc}
      end)

    deps_functions
  end

  defp check_deps_order(
         {:defp, _meta,
          [{function_name, _function_meta, _args}, [do: {:__block__, _block_meta, deps_list}]]},
         issue_meta,
         sort_method
       ) do
    check_deps_list(deps_list, function_name, issue_meta, sort_method)
  end

  defp check_deps_order(
         {:defp, _meta, [{function_name, _function_meta, _args}, [do: deps_list]]},
         issue_meta,
         sort_method
       )
       when is_list(deps_list) do
    check_deps_list([deps_list], function_name, issue_meta, sort_method)
  end

  defp check_deps_order(_node, _issue_meta, _sort_method), do: []

  defp check_deps_list(deps_list, function_name, issue_meta, sort_method) do
    deps =
      deps_list
      |> List.flatten()
      |> extract_deps()

    case sort_method do
      :alpha -> check_alphabetical_order(deps, function_name, issue_meta)
    end
  end

  defp extract_deps(list) do
    Enum.flat_map(list, fn
      # Match dependency tuple: {:dep_name, ...}
      {:{}, meta, [dep_name | _rest]} when is_atom(dep_name) ->
        dep_str = to_string(dep_name)
        [{meta[:line] || 0, dep_str}]

      # Match keyword syntax
      {dep_name, _} when is_atom(dep_name) ->
        dep_str = to_string(dep_name)
        [{0, dep_str}]

      # Skip anything else
      _ ->
        []
    end)
  end

  defp check_alphabetical_order(deps, function_name, issue_meta) do
    deps
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.filter(fn [{_line1, dep1}, {_line2, dep2}] ->
      String.downcase(dep1) > String.downcase(dep2)
    end)
    |> Enum.map(fn [{line_no, dep_name} | _] ->
      issue_for(issue_meta, line_no, dep_name, function_name)
    end)
  end

  defp issue_for(issue_meta, line_no, dep_name, function_name) do
    format_issue(
      issue_meta,
      message: "The dependency #{dep_name} in #{function_name}/0 is not alphabetically ordered.",
      trigger: Credo.Issue.no_trigger(),
      line_no: line_no,
      column: 1
    )
  end
end
