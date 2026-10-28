defmodule OptimumCredo.Check.Readability.TypeParenthesesConsistency do
  @moduledoc """
  Finds type definitions and type references that break the configured parentheses style.

  Two independent styles are enforced:

  - `definition_style` (default `:bare`): `@type t :: ...` (`:bare`) or `@type t() :: ...`
    (`:parens`). Applies to `@type`, `@typep`, and `@opaque` heads without type variables.
  - `reference_style` (default `:parens`): references such as `map()` and `String.t()`
    (`:parens`) or `map` and `String.t` (`:bare`) in `@type`, `@typep`, `@opaque`, `@spec`,
    `@callback`, and `@macrocallback`.

  A bare name is indistinguishable from a type variable in the AST, so bare references
  are only reported when the name is a built-in type (`map`, `term`, `binary`, ...) or
  a type defined in the same file. Type variables, `name :: type` annotations, and
  binary pattern contents (`<<_::binary>>`) are never reported. Types defined in other
  files are covered only in their remote form (`Mod.t`).

  ## Parameters

  - `definition_style`: `:bare` or `:parens`.
  - `reference_style`: `:parens` or `:bare`.
  """

  use Credo.Check,
    base_priority: :low,
    category: :readability,
    param_defaults: [definition_style: :bare, reference_style: :parens],
    explanations: [
      check: """
      Keep type syntax consistent: by default definitions have no parentheses and
      references do.

      ## Bad

      ```elixir
      @type t() :: %__MODULE__{}
      @spec run(map) :: String.t
      ```

      ## Good

      ```elixir
      @type t :: %__MODULE__{}
      @spec run(map()) :: String.t()
      ```

      Both styles are configurable. Bare references are only detected for built-in
      types and types defined in the same file, because type variables look identical.
      """,
      params: [
        definition_style: "`:bare` (`@type t ::`) or `:parens` (`@type t() ::`).",
        reference_style: "`:parens` (`map()`) or `:bare` (`map`)."
      ]
    ]

  @builtin_types ~w(term any none atom map pid port reference struct tuple float integer
                    neg_integer non_neg_integer pos_integer list nonempty_list
                    maybe_improper_list nonempty_improper_list nonempty_maybe_improper_list
                    binary bitstring boolean byte char charlist nonempty_charlist fun function
                    identifier iodata iolist keyword mfa module no_return node number timeout
                    arity nonempty_binary nonempty_bitstring nonempty_string)a

  @definitions [:type, :typep, :opaque]
  @specs [:spec, :callback, :macrocallback]
  @ignored [:{}, :%{}, :%, :<<>>, :__aliases__, :_, :.., :|, :->, :"::", :__block__]

  @doc false
  @spec run(Credo.SourceFile.t(), keyword()) :: [Credo.Issue.t()]
  def run(%Credo.SourceFile{} = source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)

    styles = {style(params, :definition_style), style(params, :reference_style)}

    ast = Credo.SourceFile.ast(source_file)
    known = MapSet.new(@builtin_types ++ local_types(ast))

    ast
    |> typespecs()
    |> Enum.flat_map(&typespec_issues(&1, styles, known))
    |> Enum.uniq()
    |> Enum.map(fn {message, line} ->
      format_issue(issue_meta, message: message, line_no: line)
    end)
  end

  defp style(params, key) do
    params
    |> Params.get(key, __MODULE__)
    |> style!(key)
  end

  defp typespec_issues({kind, spec, line}, {definition_style, reference_style}, known) do
    definition_issues(kind, spec, definition_style) ++
      reference_issues(
        kind,
        spec,
        reference_style,
        MapSet.difference(known, variables(kind, spec)),
        line
      )
  end

  defp style!(value, _param) when value in [:bare, :parens], do: value
  defp style!("bare", _param), do: :bare
  defp style!("parens", _param), do: :parens

  defp style!(value, param) do
    raise ArgumentError,
          "invalid #{param} #{inspect(value)} for #{inspect(__MODULE__)}; use :bare or :parens"
  end

  # Type variables of one typespec (`@type wrapper(t)`, `when t: term()`) shadow local types.
  defp variables(kind, {:when, _meta, [spec, constraints]}) do
    names = if Keyword.keyword?(constraints), do: Keyword.keys(constraints), else: []

    kind
    |> variables(spec)
    |> MapSet.union(MapSet.new(names))
  end

  defp variables(kind, {:"::", _meta, [{_name, _tuple_meta, args}, _body]})
       when kind in @definitions and is_list(args) do
    for {name, _meta, context} <- args,
        is_atom(name),
        is_atom(context),
        into: MapSet.new(),
        do: name
  end

  defp variables(_kind, _spec), do: MapSet.new()

  defp typespecs(ast) do
    {_ast, found} =
      Macro.prewalk(ast, [], fn
        {:@, meta, [{kind, _meta, [spec]}]} = node, acc
        when kind in @definitions or kind in @specs ->
          {node, [{kind, spec, meta[:line] || 1} | acc]}

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(found)
  end

  defp local_types(ast) do
    ast
    |> typespecs()
    |> Enum.flat_map(fn
      {kind, {:"::", _meta, [{name, _tuple_meta, _args}, _body]}, _line}
      when kind in @definitions and is_atom(name) ->
        [name]

      _other ->
        []
    end)
  end

  defp definition_issues(kind, {:"::", _meta, [{name, meta, args}, _body]}, style)
       when kind in @definitions and is_atom(name) do
    case {args, style} do
      {[], :bare} ->
        [
          {"Write the definition of type #{name} without parentheses: @#{kind} #{name} ::",
           meta[:line] || 1}
        ]

      {args, :parens} when is_atom(args) ->
        [
          {"Write the definition of type #{name} with parentheses: @#{kind} #{name}() ::",
           meta[:line] || 1}
        ]

      _other ->
        []
    end
  end

  defp definition_issues(_kind, _spec, _style), do: []

  defp reference_issues(kind, spec, style, known, line) do
    spec
    |> reference_nodes(kind)
    |> Enum.flat_map(&reference_message(&1, style, known, line))
  end

  defp reference_message({name, :bare, ref_line}, :parens, known, line) do
    if known?(name, known), do: [bare_message(name, ref_line || line)], else: []
  end

  defp reference_message({name, :parens, ref_line}, :bare, _known, line) do
    [parens_message(name, ref_line || line)]
  end

  defp reference_message(_node, _style, _known, _line), do: []

  defp known?(name, known) when is_atom(name), do: MapSet.member?(known, name)
  defp known?(_remote_name, _known), do: true

  defp bare_message(name, line),
    do: {"Write type reference #{name} with parentheses: #{name}().", line}

  defp parens_message(name, line), do: {"Write type reference #{name} without parentheses.", line}

  # Type bodies to scan for references; heads, annotations and type variables are skipped.
  defp reference_nodes({:"::", _meta, [{_name, _tuple_meta, args}, body]}, kind)
       when kind in @definitions or kind in @specs do
    head_refs =
      if kind in @definitions,
        do: [],
        else: if(is_list(args), do: Enum.flat_map(args, &refs/1), else: [])

    head_refs ++ refs(body)
  end

  defp reference_nodes({:when, _meta, [spec, constraints]}, kind) when kind in @specs do
    values = if Keyword.keyword?(constraints), do: Enum.map(constraints, &elem(&1, 1)), else: []
    reference_nodes(spec, kind) ++ Enum.flat_map(values, &refs/1)
  end

  defp reference_nodes(_spec, _kind), do: []

  defp refs({:<<>>, _meta, _args}), do: []
  defp refs({:"::", _meta, [_annotation, type]}), do: refs(type)
  defp refs({:__aliases__, _meta, _segments}), do: []

  defp refs({{:., _dot, [module, name]}, meta, args}) when is_atom(name) and is_list(args) do
    case args do
      [] ->
        [{remote_name(module, name), if(meta[:no_parens], do: :bare, else: :parens), meta[:line]}]

      _args ->
        Enum.flat_map(args, &refs/1)
    end
  end

  defp refs({name, meta, args}) when is_atom(name) and name not in @ignored and is_atom(args) do
    if dunder?(name), do: [], else: [{name, :bare, meta[:line]}]
  end

  defp refs({name, meta, []}) when is_atom(name) and name not in @ignored,
    do: [{name, :parens, meta[:line]}]

  defp refs({_name, _meta, args}) when is_list(args), do: Enum.flat_map(args, &refs/1)
  defp refs({left, right}), do: refs(left) ++ refs(right)
  defp refs(list) when is_list(list), do: Enum.flat_map(list, &refs/1)
  defp refs(_other), do: []

  defp dunder?(name) do
    name
    |> Atom.to_string()
    |> String.starts_with?("__")
  end

  defp remote_name(module, name), do: "#{Macro.to_string(module)}.#{name}"
end
