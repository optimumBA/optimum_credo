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
  @spec run(Credo.SourceFile.t(), keyword()) :: [Credo.Issue.t()]
  def run(%Credo.SourceFile{} = source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)

    Credo.Code.prewalk(
      source_file,
      &traverse(&1, &2, issue_meta)
    )
  end

  defp traverse({:defmodule, _meta, [_name, [do: body]]} = ast, issues, issue_meta) do
    found =
      body
      |> module_nodes()
      |> check_extractable_spec_types(issue_meta)

    {ast, issues ++ found}
  end

  defp traverse(ast, issues, _issue_meta), do: {ast, issues}

  # Nodes of this module's own body (including compile-time conditionals), but not nested
  # modules, which are checked on their own.
  defp module_nodes(body) do
    {_ast, nodes} =
      Macro.prewalk(body, [], fn
        {:defmodule, _meta, _args}, nodes -> {:skip, nodes}
        node, nodes -> {node, [node | nodes]}
      end)

    Enum.reverse(nodes)
  end

  defp check_extractable_spec_types(nodes, issue_meta) do
    existing_types = extract_existing_type_names(nodes)
    aliased_types = extract_aliased_types(nodes)
    type_usage = extract_spec_type_usage(nodes)

    type_usage
    |> Enum.sort_by(fn {_type_string, [line | _tail]} -> line end)
    |> Enum.flat_map(fn {type_string, occurrences} ->
      first_line = hd(occurrences)

      if type_string in aliased_types or type_already_defined?(type_string, existing_types) do
        []
      else
        suggested_name = suggest_type_name(type_string)

        [
          issue_for(
            issue_meta,
            first_line,
            "Extract common type '#{type_string}' to semantic alias: " <>
              "'@type #{suggested_name} :: #{type_string}'"
          )
        ]
      end
    end)
  end

  defp extract_existing_type_names(nodes) do
    nodes
    |> Enum.flat_map(fn
      {:@, _meta,
       [{:type, _type_meta, [{:"::", _ignored, [{name, _tuple_meta, _args}, _type_def]}]}]}
      when is_atom(name) ->
        [Atom.to_string(name)]

      _ignored ->
        []
    end)
    |> MapSet.new()
  end

  # Types the module has already extracted, possibly under another name than the suggested
  # one (`@type attrs :: map()`).
  defp extract_aliased_types(nodes) do
    for {:@, _meta,
         [{:type, _type_meta, [{:"::", _ignored, [{name, _tuple_meta, _args}, type_def]}]}]} <-
          nodes,
        is_atom(name),
        type_string = type_string(type_def),
        into: MapSet.new(),
        do: type_string
  end

  defp type_string({{:., _meta, [module_alias, :t]}, _tuple_meta, []}) do
    if name = format_module_alias(module_alias), do: "#{name}.t()"
  end

  defp type_string({type_name, _meta, []}) when is_atom(type_name) do
    type_string = "#{type_name}()"
    if should_extract_type?(type_string), do: type_string
  end

  defp type_string(_other), do: nil

  defp extract_spec_type_usage(nodes) do
    nodes
    |> Enum.flat_map(fn
      {:@, meta, [{:spec, _meta, spec_content}]} ->
        line = meta[:line] || 1
        extract_types_from_spec_ast(spec_content, line)

      _ignored ->
        []
    end)
    |> Enum.group_by(fn {type, _line} -> type end)
    |> Enum.map(fn {type, type_line_pairs} ->
      lines = Enum.map(type_line_pairs, fn {_type, line} -> line end)
      {type, Enum.sort(lines)}
    end)
  end

  defp extract_types_from_spec_ast(ast, line) do
    {_ast, types} =
      Macro.prewalk(ast, [], fn node, acc ->
        case type_string(node) do
          nil -> {node, acc}
          type_string -> {node, [{type_string, line} | acc]}
        end
      end)

    types
  end

  # Only plain aliases such as `Plug.Conn`. `__MODULE__.t()` is the module's own type and
  # an Erlang `:ets.t()` has no semantic alias to suggest.
  defp format_module_alias({:__aliases__, _meta, aliases}) do
    if Enum.all?(aliases, &is_atom/1), do: Enum.join(aliases, ".")
  end

  defp format_module_alias(_other), do: nil

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
  defp suggest_type_name("list()"), do: "list_type"
  defp suggest_type_name("tuple()"), do: "tuple_type"
  defp suggest_type_name("pid()"), do: "process_id"
  defp suggest_type_name("reference()"), do: "reference_id"
  defp suggest_type_name("binary()"), do: "binary_data"

  defp suggest_type_name(type_string) do
    # For other types, extract a reasonable name
    type_string
    |> String.replace(~r/\.t\(\)$/, "")
    |> String.replace(~r/\(\)$/, "")
    |> String.split(".")
    |> List.last()
    |> String.downcase()
    |> avoid_builtin_type_name()
  end

  defp avoid_builtin_type_name(name) do
    elixir_types = ~w(charlist nonempty_charlist keyword struct as_boolean)

    if name in elixir_types or erlang_type?(name) do
      name <> "_type"
    else
      name
    end
  rescue
    ArgumentError -> name
  end

  defp erlang_type?(name) do
    name
    |> String.to_existing_atom()
    |> :erl_internal.is_type(0)
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
