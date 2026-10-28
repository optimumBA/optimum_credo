defmodule OptimumCredo.Check.Refactor.RepeatedLiteral do
  @moduledoc """
  Finds string literals repeated several times in one module.

  A string is counted when it appears as a plain literal in expressions (call arguments,
  map values, comparisons) at least `min_occurrences` times within a module and has at least
  `min_length` characters. Not counted: interpolated strings and sigils (so HEEx and class
  lists), function heads and `case`/`with`/`for` patterns (the left side of `=` and `<-`),
  map keys (`%{"url" => v}`, `params["id"]`), `attr`/`slot`/`plug` declarations (declarative
  DSL entries that stand alone), module-attribute definitions, `@doc`-style
  attributes, `import`/`alias`/`use`/`require`, and the `ignore_paths` (tests by default).

  Mix dependency version requirements are independent package policies, not shared
  runtime values: literal requirements in `deps/0` and `*_deps/0` in `mix.exs` are
  not counted. Other literals in those functions remain checked. Literal `lock:`
  options in Ecto `from` queries are also excluded: Ecto requires the lock clause
  to remain literal; extracting it to an attribute can prevent compilation.

  Nested modules are counted separately. One issue is reported per repeated literal, at its
  first occurrence. Whether a literal deserves a module attribute is a judgement call; this
  check only flags repetition.

  ## Parameters

  - `min_occurrences` (default `3`), `min_length` (default `3`).
  - `ignore_literals`: strings that never count.
  - `ignore_paths`: directory/suffix patterns to skip.
  """

  use Credo.Check,
    base_priority: :low,
    category: :refactor,
    param_defaults: [
      min_occurrences: 3,
      min_length: 3,
      ignore_literals: [],
      ignore_paths: ["test/", "priv/", "config/", "_test.exs"]
    ],
    explanations: [
      check: """
      A string literal repeated in a module is a candidate for a named module attribute.
      Single obvious literals stay inline; this check only counts repeated plain strings
      outside patterns, attributes, sigils and tests. Opt-in, low priority.
      """,
      params: [
        min_occurrences: "How many identical literals trigger the check.",
        min_length: "Shortest string that is counted.",
        ignore_literals: "Strings that are never counted.",
        ignore_paths: "Directory (ending in `/`) or file-suffix patterns to skip."
      ]
    ]

  alias OptimumCredo.OptimumIdiomsSupport

  @skipped_forms [
    :@,
    :import,
    :alias,
    :use,
    :require,
    :sigil_H,
    :sigil_L,
    :sigil_E,
    :attr,
    :slot,
    :plug
  ]

  @doc false
  @spec run(Credo.SourceFile.t(), keyword()) :: [Credo.Issue.t()]
  def run(%Credo.SourceFile{} = source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)
    ignore_paths = Params.get(params, :ignore_paths, __MODULE__)

    if OptimumIdiomsSupport.heex_file?(source_file) or
         OptimumIdiomsSupport.path_matches?(source_file.filename, ignore_paths) do
      []
    else
      options = %{
        min_occurrences: Params.get(params, :min_occurrences, __MODULE__),
        min_length: Params.get(params, :min_length, __MODULE__),
        ignored: Params.get(params, :ignore_literals, __MODULE__),
        mix_project?: Path.basename(source_file.filename) == "mix.exs"
      }

      source_file
      |> Credo.Code.prewalk(&collect_bodies/2)
      |> Enum.flat_map(&repeated_issues(&1, options, issue_meta))
      |> Enum.sort_by(& &1.line_no)
    end
  end

  defp collect_bodies({:defmodule, _meta, [_name, [do: body]]} = node, acc),
    do: {node, [body | acc]}

  defp collect_bodies(node, acc), do: {node, acc}

  defp repeated_issues(body, options, issue_meta) do
    body
    |> without_dependency_versions(options.mix_project?)
    |> literals(1, [])
    |> Enum.reject(fn {text, _line} ->
      String.length(text) < options.min_length or text in options.ignored
    end)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.filter(fn {_text, lines} -> length(lines) >= options.min_occurrences end)
    |> Enum.map(fn {text, lines} ->
      format_issue(issue_meta,
        message:
          "String #{inspect(text)} appears #{length(lines)} times in this module; consider a module attribute.",
        line_no: Enum.min(lines)
      )
    end)
  end

  defp without_dependency_versions(body, false), do: body

  defp without_dependency_versions(body, true) do
    Macro.prewalk(body, fn
      {kind, meta, [{name, _head_meta, _args} = head, [do: content]]} = node
      when kind in [:def, :defp] and is_atom(name) ->
        if name == :deps or String.ends_with?(Atom.to_string(name), "_deps") do
          {kind, meta, [head, [do: strip_requirements(content)]]}
        else
          node
        end

      node ->
        node
    end)
  end

  defp strip_requirements(body) do
    Macro.prewalk(body, fn
      {app, version} = tuple when is_atom(app) and is_binary(version) ->
        if valid_requirement?(version), do: {app, nil}, else: tuple

      {:{}, meta, [app, version, opts]} = tuple when is_atom(app) and is_binary(version) ->
        if valid_requirement?(version), do: {:{}, meta, [app, nil, opts]}, else: tuple

      node ->
        node
    end)
  end

  defp valid_requirement?(version),
    do: match?({:ok, _requirement}, Version.parse_requirement(version))

  defp query_literals(args, line, acc) do
    Enum.reduce(args, acc, fn argument, acc ->
      argument =
        if is_list(argument) and Keyword.keyword?(argument),
          do: Keyword.delete(argument, :lock),
          else: argument

      literals(argument, line, acc)
    end)
  end

  # Collects `{string, line}` for literals in expression position, without descending into
  # nested modules (counted on their own), patterns, attributes, sigils or interpolations.
  # Plain strings carry no metadata, so the line is that of the nearest enclosing call.
  defp literals({:defmodule, _meta, _args}, _line, acc), do: acc
  defp literals({form, _meta, _args}, _line, acc) when form in @skipped_forms, do: acc
  defp literals({:<<>>, _meta, _args}, _line, acc), do: acc

  defp literals({:from, meta, args}, line, acc) when is_list(args),
    do: query_literals(args, meta[:line] || line, acc)

  defp literals(
         {{:., _dot, [{:__aliases__, _alias_meta, [:Ecto, :Query]}, :from]}, meta, args},
         line,
         acc
       )
       when is_list(args),
       do: query_literals(args, meta[:line] || line, acc)

  # `target["key"]`: the key names a field, it is not a magic value.
  defp literals({{:., _meta, [Access, :get]}, meta, [target, _key]}, line, acc),
    do: literals(target, meta[:line] || line, acc)

  # `%{"key" => value}`: only values count.
  defp literals({:%{}, meta, pairs}, line, acc) when is_list(pairs) do
    Enum.reduce(pairs, acc, fn pair, acc ->
      pair
      |> map_value()
      |> literals(meta[:line] || line, acc)
    end)
  end

  defp literals({:->, meta, [_patterns, body]}, line, acc),
    do: literals(body, meta[:line] || line, acc)

  defp literals({kind, meta, [_head, body]}, line, acc)
       when kind in [:def, :defp, :defmacro, :defmacrop],
       do: literals(body, meta[:line] || line, acc)

  defp literals({match, meta, [_pattern, value]}, line, acc) when match in [:=, :<-],
    do: literals(value, meta[:line] || line, acc)

  defp literals({form, meta, args}, line, acc) when is_list(args),
    do: literals(args, meta[:line] || line, literals(form, line, acc))

  defp literals({left, right}, line, acc), do: literals(right, line, literals(left, line, acc))

  defp literals(list, line, acc) when is_list(list),
    do: Enum.reduce(list, acc, &literals(&1, line, &2))

  defp literals(text, line, acc) when is_binary(text), do: [{text, line} | acc]
  defp literals(_other, _line, acc), do: acc

  defp map_value({_key, value}), do: value
  defp map_value(other), do: other
end
