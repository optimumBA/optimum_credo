defmodule OptimumCredo.Check.Readability.ExtractableSpecTypes do
  @moduledoc """
  A check that finds common type patterns in @spec declarations that should be extracted to module-level @type aliases.

  This check identifies when common types like Plug.Conn.t(), map(), String.t() are used directly
  in @spec declarations and suggests extracting them to semantic type aliases at the module top.
  This enforces consistent, readable code style regardless of repetition.
  """

  use Credo.Check,
    base_priority: :low,
    category: :readability,
    explanations: [
      check: """
      Common types in @spec declarations should be extracted to module-level semantic type aliases
      for better readability, maintainability and consistency.

      ## Examples

      **Bad:**
      ```elixir
      @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t()
      @spec index(Plug.Conn.t(), map()) :: Plug.Conn.t()
      ```

      **Good:**
      ```elixir
      @type conn :: Plug.Conn.t()
      @type params :: map()

      @spec show(conn(), params()) :: conn()
      @spec index(conn(), params()) :: conn()
      ```

      This provides semantic meaning and ensures consistency across all modules.
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
    new_issues = check_extractable_spec_types(module_body, issue_meta)
    {ast, issues ++ new_issues}
  end

  defp traverse(ast, issues, _issue_meta) do
    {ast, issues}
  end

  defp check_extractable_spec_types(module_body, issue_meta) do
    existing_types = extract_existing_type_names(module_body)
    type_usage = extract_spec_type_usage(module_body)

    type_usage
    |> Enum.filter(fn {type_string, _occurrences} ->
      not type_already_defined?(type_string, existing_types)
    end)
    |> Enum.map(fn {type_string, occurrences} ->
      first_line = hd(occurrences)
      suggested_name = suggest_type_name(type_string)

      issue_for(
        issue_meta,
        first_line,
        "Extract common type '#{type_string}' to semantic alias: " <>
          "'@type #{suggested_name} :: #{type_string}'"
      )
    end)
  end

  defp extract_existing_type_names(module_body) do
    module_body
    |> Enum.flat_map(fn
      {:@, _meta, [{:type, _, [{:"::", _, [{name, _, _}, _type_def]}]}]} when is_atom(name) ->
        [Atom.to_string(name)]

      _ ->
        []
    end)
    |> MapSet.new()
  end

  defp extract_spec_type_usage(module_body) do
    module_body
    |> Enum.flat_map(fn
      {:@, meta, [{:spec, _, spec_content}]} ->
        line = meta[:line] || 1
        extract_types_from_spec_ast(spec_content, line)

      _ ->
        []
    end)
    |> Enum.group_by(fn {type, _line} -> type end)
    |> Enum.map(fn {type, type_line_pairs} ->
      lines = Enum.map(type_line_pairs, fn {_type, line} -> line end)
      {type, lines}
    end)
  end

  defp extract_types_from_spec_ast(ast, line) do
    {_ast, types} =
      Macro.prewalk(ast, [], fn
        # Match complex types like Plug.Conn.t()
        {{:., _, [module_alias, :t]}, _, []} = node, acc ->
          type_string = "#{format_module_alias(module_alias)}.t()"
          {node, [{type_string, line} | acc]}

        # Match simple types like map(), String.t(), keyword(), etc.
        {type_name, _, []} = node, acc when is_atom(type_name) ->
          type_string = "#{type_name}()"
          # Only include common types that benefit from extraction
          if should_extract_type?(type_string) do
            {node, [{type_string, line} | acc]}
          else
            {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    types
  end

  defp format_module_alias({:__aliases__, _, aliases}) do
    Enum.join(aliases, ".")
  end

  defp format_module_alias(alias) when is_atom(alias) do
    "#{alias}"
  end

  defp should_extract_type?(type_string) do
    # Types that commonly benefit from extraction
    extractable_types = [
      "map()",
      "keyword()",
      "String.t()",
      "integer()",
      "atom()",
      "list()",
      "tuple()",
      "pid()",
      "reference()",
      "binary()",
      "Plug.Conn.t()",
      "Phoenix.LiveView.Socket.t()",
      "Ecto.Changeset.t()"
    ]

    # Check if it's in our list or follows module pattern (*.t())
    type_string in extractable_types or
      String.match?(type_string, ~r/^[A-Z][a-zA-Z0-9.]*\.t\(\)$/)
  end

  defp suggest_type_name("Plug.Conn.t()"), do: "conn"
  defp suggest_type_name("map()"), do: "params"
  defp suggest_type_name("keyword()"), do: "opts"
  defp suggest_type_name("String.t()"), do: "text"
  defp suggest_type_name("integer()"), do: "count"
  defp suggest_type_name("atom()"), do: "status"
  defp suggest_type_name("Phoenix.LiveView.Socket.t()"), do: "socket"
  defp suggest_type_name("Ecto.Changeset.t()"), do: "changeset"

  defp suggest_type_name(type_string) do
    # For other types, extract a reasonable name
    type_string
    |> String.replace(~r/\.t\(\)$/, "")
    |> String.replace(~r/\(\)$/, "")
    |> String.split(".")
    |> List.last()
    |> String.downcase()
  end

  defp type_already_defined?(type_string, existing_types) do
    suggested_name = suggest_type_name(type_string)
    MapSet.member?(existing_types, suggested_name)
  end

  defp issue_for(issue_meta, line_no, message) do
    format_issue(
      issue_meta,
      message: message,
      line_no: line_no
    )
  end
end
