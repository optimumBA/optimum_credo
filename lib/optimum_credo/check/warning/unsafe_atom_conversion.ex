defmodule OptimumCredo.Check.Warning.UnsafeAtomConversion do
  @moduledoc """
  Finds conversions that create atoms from runtime strings: `String.to_atom/1`,
  `List.to_atom/1`, `:erlang.binary_to_atom/1,2` and `:erlang.list_to_atom/1`.

  Atoms are never garbage collected, so converting request data to atoms lets a client
  exhaust the atom table and crash the VM. Use `String.to_existing_atom/1` (and rescue),
  an explicit mapping, or keep strings.

  This is a syntactic check; it cannot know where the string comes from. It does not report:

  - files under `config/` or `priv/repo/`, nor paths listed in `allow_in_paths`;
  - conversions in a module attribute initialiser (`@types String.to_atom("a")`), which run once
    at compile time;
  - a conversion of a string or charlist literal (`String.to_atom("admin")`, also piped), which
    creates a fixed atom;
  - a call on a line with a `# sobelow_skip` comment, or on the line after a comment-only
    `# sobelow_skip` / `# credo:disable-for-next-line` line. A trailing comment belongs to its
    own line only. `sobelow_skip` with a rule list must name `"DOS.StringToAtom"`. A
    `# sobelow_skip` comment directly above a `def` covers the whole function, as in Sobelow;
  - anything inside `unquote(...)`, which runs while a macro expands;

  Conversions of interpolated strings, variables and piped values are reported. The capture
  `&String.to_atom/1` is reported too.

  ## Parameters

  - `allow_in_paths`: extra directory fragments to skip, like `["lib/my_app/dsl/"]`.
  """

  use Credo.Check,
    base_priority: :low,
    category: :warning,
    param_defaults: [allow_in_paths: []],
    explanations: [
      check: """
      Do not create atoms from runtime data.

      ## Bad

      ```elixir
      sort_by = String.to_atom(params["sort_by"])
      ```

      ## Good

      ```elixir
      sort_by = String.to_existing_atom(params["sort_by"])
      ```

      Suppress deliberate uses with a trailing `# sobelow_skip ["DOS.StringToAtom"]` comment.
      """,
      params: [allow_in_paths: "Extra directory fragments that are not checked."]
    ]

  alias OptimumCredo.OptimumDataSupport

  @conversions [
    {[:String], :to_atom},
    {[:List], :to_atom},
    {:erlang, :binary_to_atom},
    {:erlang, :list_to_atom}
  ]
  @doc false
  @spec run(Credo.SourceFile.t(), keyword()) :: [Credo.Issue.t()]
  def run(%Credo.SourceFile{} = source_file, params) do
    allowed =
      params
      |> Params.get(:allow_in_paths, __MODULE__)
      |> List.wrap()

    skipped = ["config/", "priv/repo/"] ++ allowed

    if OptimumDataSupport.in_any_dir?(source_file, skipped) do
      []
    else
      unsafe_issues(source_file, IssueMeta.for(source_file, params))
    end
  end

  defp unsafe_issues(source_file, issue_meta) do
    lines = OptimumDataSupport.code_and_comment_lines(source_file)

    source_file
    |> Credo.SourceFile.ast()
    |> without_compile_time_code()
    |> unsafe_calls(lines)
    |> Enum.map(&unsafe_issue(&1, issue_meta))
  end

  defp unsafe_calls(ast, lines) do
    by_line = Map.new(lines, fn {no, code, comment} -> {no, {code, comment}} end)
    skipped = skipped_functions(ast, lines)

    ast
    |> OptimumDataSupport.remote_calls()
    |> Enum.filter(fn {_module, _function, _args, meta} = call ->
      unsafe?(call) and not suppressed?(by_line, skipped, OptimumDataSupport.line(meta))
    end)
  end

  defp unsafe_issue({module, function, _args, meta}, issue_meta) do
    name = display(module, function)

    format_issue(issue_meta,
      message:
        "#{name} creates atoms from runtime data; use String.to_existing_atom/1 or keep strings.",
      trigger: name,
      line_no: OptimumDataSupport.line(meta)
    )
  end

  defp unsafe?({module, function, args, _meta}) do
    {module, function} in @conversions and not literal_argument?(args)
  end

  defp literal_argument?([value | _tail]), do: literal?(value)
  defp literal_argument?([]), do: false

  # A binary or charlist literal creates one fixed atom.
  defp literal?(value) when is_binary(value), do: true
  defp literal?([_head | _tail] = value), do: Enum.all?(value, &is_integer/1)
  defp literal?(_value), do: false

  # `@name expr` initialisers and `unquote(...)` fragments evaluate while compiling; a literal
  # piped in (`"admin" |> String.to_atom()`) becomes the argument it is.
  defp without_compile_time_code(ast) do
    Macro.prewalk(ast, fn
      {:@, meta, [{name, _meta, [_value]}]} when is_atom(name) ->
        {:@, meta, [{name, [], nil}]}

      {unquote, _meta, _args} when unquote in [:unquote, :unquote_splicing] ->
        nil

      {:|>, _meta, [left, {{:., _dot_meta, _args} = callee, call_meta, args}]} = node
      when is_list(args) ->
        if literal?(left), do: {callee, call_meta, [left | args]}, else: node

      node ->
        node
    end)
  end

  # Functions marked with a `# sobelow_skip` comment on the line above their head:
  # `[{first_line, last_line}]`.
  defp skipped_functions(ast, lines) do
    comment_only =
      for {no, code, comment} <- lines,
          comment,
          String.trim(code) == "",
          into: %{},
          do: {no, comment}

    {_ast, ranges} = Macro.prewalk(ast, [], &collect_skipped(&1, &2, comment_only))

    ranges
  end

  defp collect_skipped({definition, meta, [_head | _tail]} = node, acc, comment_only)
       when definition in [:def, :defp, :defmacro, :defmacrop] do
    line = OptimumDataSupport.line(meta)
    last = get_in(meta, [:end, :line]) || line
    previous_comment = Map.get(comment_only, line - 1)

    if suppression?(previous_comment),
      do: {node, [{line, last} | acc]},
      else: {node, acc}
  end

  defp collect_skipped(node, acc, _comment_only), do: {node, acc}

  # The same line, or a comment-only line above. A trailing comment on the previous line
  # belongs to that line's code.
  defp suppressed?(by_line, skipped, line) do
    Enum.any?(skipped, fn {first, last} -> line in first..last end) or
      trailing_suppression?(by_line[line]) or comment_only_suppression?(by_line[line - 1])
  end

  defp trailing_suppression?({_code, comment}), do: suppression?(comment)
  defp trailing_suppression?(nil), do: false

  defp comment_only_suppression?({code, comment}),
    do: String.trim(code) == "" and suppression?(comment)

  defp comment_only_suppression?(nil), do: false

  # `# sobelow_skip` alone skips everything; with a list it must name `DOS.StringToAtom`.
  defp suppression?(nil), do: false

  defp suppression?(comment) do
    String.contains?(comment, "credo:disable-for-next-line") or
      case Regex.run(~r/sobelow_skip(?:\s*\[([^\]]*)\])?/, comment) do
        [_match] -> true
        [_match, rules] -> String.contains?(rules, "DOS.StringToAtom")
        nil -> false
      end
  end

  defp display(module, function) when is_atom(module), do: ":#{module}.#{function}"
  defp display(segments, function), do: "#{Enum.join(segments, ".")}.#{function}"
end
