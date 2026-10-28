defmodule OptimumCredo.Check.Readability.UnusedTypes do
  @moduledoc """
  A check that finds @type definitions that are never used in the module.

  This check identifies type definitions that are declared but never referenced
  in @spec declarations or function bodies within the same module. Types may be
  referenced with parentheses (`conn()`) or bare (`conn`); type variables (definition
  parameters and `when` keys) are not references to local types.

  Public `@type`s are part of a module's API, so the conventional `t` type
  (`@type t :: %__MODULE__{}`) is not reported by default; see `:ignored_types`.
  """

  use Credo.Check,
    base_priority: :low,
    category: :readability,
    param_defaults: [ignored_types: [:t]],
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
      """,
      params: [
        ignored_types:
          "Type names that are never reported, because other modules are expected to reference them."
      ]
    ]

  @spec_attributes [:spec, :callback, :macrocallback, :type, :typep, :opaque]

  @doc false
  @spec run(Credo.SourceFile.t(), keyword()) :: [Credo.Issue.t()]
  def run(%Credo.SourceFile{} = source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)

    ignored =
      params
      |> Params.get(:ignored_types, __MODULE__)
      |> Enum.map(&to_string/1)

    Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta, ignored))
  end

  defp traverse({:defmodule, _meta, [_name, [do: body]]} = ast, issues, issue_meta, ignored) do
    {ast, issues ++ check_unused_types(body, issue_meta, ignored)}
  end

  defp traverse(ast, issues, _issue_meta, _ignored), do: {ast, issues}

  defp check_unused_types(body, issue_meta, ignored) do
    nodes = module_nodes(body)
    used_types = extract_used_types(nodes)

    nodes
    |> extract_type_definitions()
    |> Enum.reject(fn {type_name, _line} ->
      type_name in ignored or MapSet.member?(used_types, type_name)
    end)
    |> Enum.map(fn {type_name, line} ->
      issue_for(issue_meta, line, "Unused type definition: #{type_name}")
    end)
  end

  # All nodes of this module's own body, including code nested in compile-time
  # conditionals (`if`, `case`, ...), but not the bodies of nested modules:
  # types are module-local, so a nested module cannot use them.
  defp module_nodes(body) do
    {_ast, nodes} =
      Macro.prewalk(body, [], fn
        {:defmodule, _meta, _args}, nodes -> {:skip, nodes}
        node, nodes -> {node, [node | nodes]}
      end)

    Enum.reverse(nodes)
  end

  defp extract_type_definitions(nodes) do
    Enum.flat_map(nodes, fn
      {:@, meta, [{:type, _meta, [{:"::", _type_meta, [{name, _tuple_meta, _args}, _type_def]}]}]}
      when is_atom(name) ->
        [{Atom.to_string(name), meta[:line] || 1}]

      _ignored ->
        []
    end)
  end

  defp extract_used_types(nodes) do
    Enum.reduce(nodes, MapSet.new(), &extract_types_from_statement/2)
  end

  defp extract_types_from_statement({:@, _meta, [{attr, _tuple_meta, [definition]}]}, acc)
       when attr in [:type, :typep, :opaque] do
    type_definition_refs(definition, acc)
  end

  defp extract_types_from_statement({:@, _meta, [{attr, _tuple_meta, content}]}, acc)
       when attr in @spec_attributes and is_list(content) do
    Enum.reduce(content, acc, &spec_refs(&1, [], &2))
  end

  defp extract_types_from_statement({kind, _meta, [signature, blocks]}, acc)
       when kind in [:def, :defp, :defmacro, :defmacrop] and is_list(blocks) do
    acc =
      case signature do
        {:when, _meta, [_signature, guard]} -> extract_calls_from_ast(guard, acc)
        _other -> acc
      end

    extract_calls_from_ast(blocks, acc)
  end

  defp extract_types_from_statement(_ignored, acc), do: acc

  # Function bodies only reference types through calls such as `conn()`.
  defp extract_calls_from_ast(ast, acc) do
    {_ast, types} =
      Macro.prewalk(ast, acc, fn
        {type_name, _meta, args} = node, types when is_atom(type_name) and is_list(args) ->
          {node, MapSet.put(types, Atom.to_string(type_name))}

        node, types ->
          {node, types}
      end)

    types
  end

  # `@type pair(a) :: {a, a}`: the parameters of the definition are type variables.
  defp type_definition_refs({:"::", _meta, [{_name, _tuple_meta, params}, type_def]}, acc) do
    type_refs(type_def, bound_variables(params), acc)
  end

  defp type_definition_refs(other, acc), do: type_refs(other, [], acc)

  defp bound_variables(params) when is_list(params) do
    for {name, _meta, context} <- params, is_atom(name), is_atom(context), do: name
  end

  defp bound_variables(_params), do: []

  # `@spec f(a) :: a when a: var`: the `when` keys are type variables, their bounds are types.
  defp spec_refs({:when, _meta, [spec, bounds]}, _bound, acc) when is_list(bounds) do
    bound = for {name, _value} <- bounds, is_atom(name), do: name

    acc =
      Enum.reduce(bounds, acc, fn {_name, bound_type}, acc ->
        type_refs(bound_type, bound, acc)
      end)

    spec_refs(spec, bound, acc)
  end

  # The function name of a spec head is not a type reference.
  defp spec_refs({:"::", _meta, [{name, _tuple_meta, args}, return]}, bound, acc)
       when is_atom(name) and is_list(args) do
    acc = type_refs(args, bound, acc)
    type_refs(return, bound, acc)
  end

  defp spec_refs(other, bound, acc), do: type_refs(other, bound, acc)

  # Local types are referenced as `conn()`, `pair(integer())` or bare `conn`.
  defp type_refs({:"::", _meta, [{name, _tuple_meta, context}, type]}, bound, acc)
       when is_atom(name) and is_atom(context),
       do: type_refs(type, bound, acc)

  defp type_refs({name, _meta, context}, bound, acc) when is_atom(name) and is_atom(context) do
    if name in bound, do: acc, else: MapSet.put(acc, Atom.to_string(name))
  end

  defp type_refs({name, _meta, args}, bound, acc) when is_atom(name) and is_list(args) do
    type_refs(args, bound, MapSet.put(acc, Atom.to_string(name)))
  end

  defp type_refs({call, _meta, args}, bound, acc) when is_list(args) do
    type_refs(args, bound, type_refs(call, bound, acc))
  end

  defp type_refs(tuple, bound, acc) when is_tuple(tuple) do
    tuple
    |> Tuple.to_list()
    |> type_refs(bound, acc)
  end

  defp type_refs(list, bound, acc) when is_list(list) do
    Enum.reduce(list, acc, &type_refs(&1, bound, &2))
  end

  defp type_refs(_other, _bound, acc), do: acc

  defp issue_for(issue_meta, line_no, message) do
    format_issue(
      issue_meta,
      message: message,
      line_no: line_no
    )
  end
end
