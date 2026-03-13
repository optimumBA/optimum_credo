defmodule OptimumCredo.Check.Readability.UnusedTypes do
  @moduledoc """
  A check that finds @type definitions that are never used in the module.

  This check identifies type definitions that are declared but never referenced
  in @spec declarations or function bodies within the same module.
  """

  use Credo.Check,
    base_priority: :low,
    category: :readability,
    explanations: [
      check: """
      Type definitions should be removed if they're not used anywhere in the module.

      ## Examples

      **Bad:**
      ```elixir
      @type short_id :: String.t()  # Never used
      @type conn :: Plug.Conn.t()

      @spec index(conn()) :: conn()
      def index(conn, _params) do
        # ...
      end
      ```

      **Good:**
      ```elixir
      @type conn :: Plug.Conn.t()

      @spec index(conn()) :: conn()
      def index(conn, _params) do
        # ...
      end
      ```
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
    new_issues = check_unused_types(module_body, issue_meta)
    {ast, issues ++ new_issues}
  end

  defp traverse(ast, issues, _issue_meta) do
    {ast, issues}
  end

  defp check_unused_types(module_body, issue_meta) do
    type_definitions = extract_type_definitions(module_body)
    used_types = extract_used_types(module_body)

    type_definitions
    |> Enum.reject(fn {type_name, _line} ->
      MapSet.member?(used_types, type_name)
    end)
    |> Enum.map(fn {type_name, line} ->
      issue_for(issue_meta, line, "Unused type definition: #{type_name}")
    end)
  end

  defp extract_type_definitions(module_body) do
    module_body
    |> Enum.flat_map(fn
      {:@, meta, [{:type, _, [{:"::", _, [{name, _, _}, _type_def]}]}]} when is_atom(name) ->
        [{Atom.to_string(name), meta[:line] || 1}]

      _ ->
        []
    end)
  end

  defp extract_used_types(module_body) do
    module_body
    |> Enum.reduce(MapSet.new(), fn statement, acc ->
      extract_types_from_statement(statement, acc)
    end)
  end

  defp extract_types_from_statement({:@, _meta, [{:spec, _, spec_content}]}, acc) do
    extract_types_from_spec(spec_content, acc)
  end

  # Extract types from @type definitions (for nested usage)
  defp extract_types_from_statement(
         {:@, _meta, [{:type, _, [{:"::", _, [_name, type_def]}]}]},
         acc
       ) do
    extract_types_from_ast(type_def, acc)
  end

  defp extract_types_from_statement({:def, _meta, [_signature, [do: body]]}, acc) do
    extract_types_from_ast(body, acc)
  end

  # Handle functions with guards: def func(args) when guard, do: body  
  defp extract_types_from_statement(
         {:def, _meta, [{:when, _, [_signature, guard]}, [do: body]]},
         acc
       ) do
    acc = extract_types_from_ast(guard, acc)
    extract_types_from_ast(body, acc)
  end

  defp extract_types_from_statement({:defp, _meta, [_signature, [do: body]]}, acc) do
    extract_types_from_ast(body, acc)
  end

  # Handle private functions with guards: defp func(args) when guard, do: body  
  defp extract_types_from_statement(
         {:defp, _meta, [{:when, _, [_signature, guard]}, [do: body]]},
         acc
       ) do
    acc = extract_types_from_ast(guard, acc)
    extract_types_from_ast(body, acc)
  end

  defp extract_types_from_statement(_, acc), do: acc

  defp extract_types_from_spec(spec_content, acc) do
    extract_types_from_ast(spec_content, acc)
  end

  defp extract_types_from_ast(ast, acc) do
    {_ast, types} =
      Macro.prewalk(ast, acc, fn
        # Match type usage like conn() in specs
        {type_name, _, []}, types when is_atom(type_name) ->
          type_str = Atom.to_string(type_name)
          {{type_name, [], []}, MapSet.put(types, type_str)}

        node, types ->
          {node, types}
      end)

    types
  end

  defp issue_for(issue_meta, line_no, message) do
    format_issue(
      issue_meta,
      message: message,
      line_no: line_no
    )
  end
end
