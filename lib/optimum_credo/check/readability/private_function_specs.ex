defmodule OptimumCredo.Check.Readability.PrivateFunctionSpecs do
  @moduledoc """
  A check that finds @spec declarations for private functions (defp).

  Private functions should not have @spec declarations as they are internal
  implementation details and not part of the module's public API.
  """

  use Credo.Check,
    base_priority: :low,
    category: :readability,
    explanations: [
      check: """
      Private functions should not have @spec declarations. Specs are for
      public API documentation and type checking, not internal implementation details.

      ## Examples

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

      Only public functions (def) should have @spec declarations.
      """
    ]

  @doc false
  def run(%Credo.SourceFile{} = source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)

    source_file
    |> Credo.Code.prewalk(&traverse(&1, &2, issue_meta))
  end

  defp traverse(
         {:defmodule, _meta, [_name, [do: {:__block__, [], module_body}]]} = ast,
         issues,
         issue_meta
       ) do
    new_issues = check_private_function_specs(module_body, issue_meta)
    {ast, issues ++ new_issues}
  end

  defp traverse(ast, issues, _issue_meta) do
    {ast, issues}
  end

  defp check_private_function_specs(module_body, issue_meta) do
    # Find all @spec declarations and their positions
    specs = extract_specs_with_positions(module_body)

    # Find all defp function names and their positions  
    private_functions = extract_private_functions(module_body)

    # Match specs to private functions
    specs
    |> Enum.filter(fn {spec_name, spec_line} ->
      Enum.any?(private_functions, fn {func_name, func_line} ->
        spec_name == func_name && spec_line < func_line && func_line - spec_line <= 5
      end)
    end)
    |> Enum.map(fn {func_name, line} ->
      issue_for(
        issue_meta,
        line,
        "Remove @spec for private function #{func_name}/#{get_function_arity(module_body, func_name)}. " <>
          "Private functions should not have @spec declarations."
      )
    end)
  end

  defp extract_specs_with_positions(module_body) do
    module_body
    |> Enum.with_index()
    |> Enum.flat_map(fn {statement, _index} ->
      case statement do
        {:@, meta, [{:spec, _, [{:"::", _, [{func_name, _, _args} | _]} | _]}]} ->
          line = meta[:line] || 1
          func_atom = extract_function_name(func_name)

          if func_atom do
            [{func_atom, line}]
          else
            []
          end

        _ ->
          []
      end
    end)
  end

  defp extract_private_functions(module_body) do
    module_body
    |> Enum.flat_map(fn
      # Handle defp with guards: defp func(args) when guard, do: body
      {:defp, meta, [{:when, _, [{func_name, _, _args} | _guards]} | _]} when is_atom(func_name) ->
        line = meta[:line] || 1
        [{func_name, line}]

      # Handle regular defp: defp func(args), do: body  
      {:defp, meta, [{func_name, _, _args} | _]} when is_atom(func_name) ->
        line = meta[:line] || 1
        [{func_name, line}]

      _ ->
        []
    end)
  end

  defp extract_function_name(func_name) when is_atom(func_name), do: func_name
  defp extract_function_name({func_name, _, _}) when is_atom(func_name), do: func_name
  defp extract_function_name(_), do: nil

  defp get_function_arity(module_body, func_name) do
    module_body
    |> Enum.find_value(fn
      {:defp, _meta, [{^func_name, _, args} | _]} when is_list(args) ->
        length(args)

      {:defp, _meta, [{^func_name, _, _args}]} ->
        # Handle case where args is not a list (e.g., single arg without list)
        1

      _ ->
        nil
    end) || "?"
  end

  defp issue_for(issue_meta, line_no, message) do
    format_issue(
      issue_meta,
      message: message,
      line_no: line_no
    )
  end
end
