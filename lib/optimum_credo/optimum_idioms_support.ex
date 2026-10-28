defmodule OptimumCredo.OptimumIdiomsSupport do
  @moduledoc false
  # Small helpers shared by the opt-in idiom checks: path scoping, pipe
  # normalisation, and HEEx text extraction from `~H` sigils and `.heex` files.

  @definitions [:def, :defp, :defmacro, :defmacrop]

  @doc "True when the file is a standalone HEEx template rather than Elixir source."
  @spec heex_file?(Credo.SourceFile.t()) :: boolean()
  def heex_file?(%Credo.SourceFile{filename: filename}), do: String.ends_with?(filename, ".heex")

  @doc """
  True when `filename` lies under one of the `patterns`. A pattern ending in `/` matches a
  directory segment anywhere in the path; other patterns match a path suffix.
  """
  @spec path_matches?(String.t(), [String.t()]) :: boolean()
  def path_matches?(filename, patterns) do
    path = "/" <> String.replace(filename, "\\", "/")

    Enum.any?(patterns, fn pattern ->
      if String.ends_with?(pattern, "/"),
        do: String.contains?(path, "/" <> pattern),
        else: String.ends_with?(path, "/" <> pattern) or String.ends_with?(path, pattern)
    end)
  end

  @doc "True for files under `test/` or named `*_test.exs`."
  @spec test_file?(String.t()) :: boolean()
  def test_file?(filename), do: path_matches?(filename, ["test/", "_test.exs"])

  @doc """
  Rewrites `a |> f(b)` into `f(a, b)` throughout `ast`, so call patterns match both forms.
  """
  @spec unpipe(Macro.t()) :: Macro.t()
  def unpipe(ast) do
    Macro.prewalk(ast, fn
      {:|>, _meta, [lhs, {call, meta, args}]} when is_list(args) -> {call, meta, [lhs | args]}
      node -> node
    end)
  end

  @doc """
  Replaces the head of every `def`/`defp`/`defmacro`/`defmacrop` and every `@attribute` with
  `nil`, so a call-shape search only sees expressions, not definitions or typespecs that happen
  to look like a call (`def assign(socket, a: 1)`, `@spec send(pid, {:ok})`).
  """
  @spec without_definition_heads(Macro.t()) :: Macro.t()
  def without_definition_heads(ast) do
    Macro.prewalk(ast, fn
      {kind, meta, [_head, body]} when kind in @definitions -> {kind, meta, [nil, body]}
      {kind, meta, [_head]} when kind in @definitions -> {kind, meta, [nil]}
      {:@, _meta, _args} -> nil
      node -> node
    end)
  end

  @doc """
  Classifies a module body: `:view` or `:component` when it `use`s Phoenix.LiveView,
  Phoenix.LiveComponent, or `use MyWeb, :live_view` / `:live_component`; otherwise `nil`.
  """
  @spec live_kind([Macro.t()]) :: :view | :component | nil
  def live_kind(statements) do
    Enum.find_value(statements, fn
      {:use, _meta, [{:__aliases__, _alias_meta, [:Phoenix, :LiveView]} | _tail]} ->
        :view

      {:use, _meta, [{:__aliases__, _alias_meta, [:Phoenix, :LiveComponent]} | _tail]} ->
        :component

      {:use, _meta, [_web, :live_view | _tail]} ->
        :view

      {:use, _meta, [_web, :live_component | _tail]} ->
        :component

      _other ->
        nil
    end)
  end

  @doc "Returns the top-level statements of a module body."
  @spec statements(Macro.t()) :: [Macro.t()]
  def statements({:__block__, _meta, list}), do: list
  def statements(nil), do: []
  def statements(single), do: [single]

  @doc "Strips line/column metadata so clauses can be compared structurally."
  @spec strip_meta(Macro.t()) :: Macro.t()
  def strip_meta(ast) do
    Macro.prewalk(ast, fn
      {form, _meta, args} -> {form, [], args}
      node -> node
    end)
  end

  @doc "Replaces nested `defmodule`s in a module body with `nil`, so a scan stays in one module."
  @spec without_nested_modules(Macro.t()) :: Macro.t()
  def without_nested_modules(body) do
    Macro.prewalk(body, fn
      {:defmodule, _meta, _args} -> nil
      node -> node
    end)
  end

  @type attr_value :: {:string | :expr | :bare, String.t()} | nil
  @type tag :: %{
          name: String.t(),
          line: pos_integer(),
          attrs: [{String.t(), attr_value(), pos_integer()}]
        }

  @doc """
  Returns the open tags found in the file's HEEx text (`~H` sigils, or the whole file for
  `.heex`, which stock Credo never delivers) as `%{name: name, line: line, attrs: [{attr_name, value, line}]}`.

  `value` is `{:string, text}` for `"..."`/`'...'`, `{:expr, text}` for `{...}`, `{:bare, text}`
  for an unquoted token and `nil` for a valueless attribute. Text inside HTML comments
  (`<!-- -->`), HEEx/EEx comments (`<%!-- --%>`, `<%# %>`), EEx tags, `<script>`/`<style>`
  bodies and `{...}` body interpolation is never read as markup. This is a conservative
  tokenizer, not a full HEEx parser: an unterminated construct ends the scan of its fragment.
  """
  @spec heex_tags(Credo.SourceFile.t()) :: [tag()]
  def heex_tags(source_file) do
    source_file
    |> heex_fragments()
    |> fragment_tags()
  end

  @doc "Same as `heex_tags/1` for the `~H` sigils found in `ast` (such as one module body)."
  @spec heex_tags_in(Macro.t()) :: [tag()]
  def heex_tags_in(ast) do
    ast
    |> sigil_fragments()
    |> fragment_tags()
  end

  defp fragment_tags(fragments) do
    Enum.flat_map(fragments, fn {text, first_line} ->
      for {:tag, tag} <- scan_markup(text, first_line), do: tag
    end)
  end

  @doc """
  Returns the file's HEEx fragments as `{text, first_line}` with comments, EEx comments and
  `<script>`/`<style>` bodies blanked out. Newlines are kept so line numbers still line up.
  """
  @spec heex_visible_text(Credo.SourceFile.t()) :: [{String.t(), pos_integer()}]
  def heex_visible_text(source_file) do
    source_file
    |> heex_fragments()
    |> Enum.map(&blank_fragment/1)
  end

  @doc "Same as `heex_visible_text/1` for the `~H` sigils found in `ast` (such as one module body)."
  @spec heex_visible_text_in(Macro.t()) :: [{String.t(), pos_integer()}]
  def heex_visible_text_in(ast) do
    ast
    |> sigil_fragments()
    |> Enum.map(&blank_fragment/1)
  end

  @doc "Returns `{text, first_line}` for each `~H` sigil (or the whole `.heex` file)."
  @spec heex_fragments(Credo.SourceFile.t()) :: [{String.t(), pos_integer()}]
  def heex_fragments(source_file) do
    if heex_file?(source_file) do
      [{Credo.SourceFile.source(source_file), 1}]
    else
      source_file
      |> Credo.SourceFile.ast()
      |> sigil_fragments()
    end
  end

  defp sigil_fragments(ast) do
    {_ast, fragments} =
      Macro.prewalk(ast, [], fn
        {:sigil_H, meta, [{:<<>>, _meta, parts}, _modifiers]} = node, acc ->
          text =
            parts
            |> Enum.filter(&is_binary/1)
            |> Enum.join()

          heredoc? = meta[:delimiter] in [~S("""), "'''"]
          {node, [{text, (meta[:line] || 1) + if(heredoc?, do: 1, else: 0)} | acc]}

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(fragments)
  end

  # --- HEEx tokenizer ---------------------------------------------------------------------

  defp blank_fragment({text, first_line}) do
    blanked =
      text
      |> scan_markup(first_line)
      |> Enum.reverse()
      |> Enum.reduce(text, fn
        {:ignored, from, to}, acc -> blank_range(acc, from, to)
        {:tag, _tag}, acc -> acc
      end)

    {blanked, first_line}
  end

  defp blank_range(text, from, to) do
    blank =
      text
      |> binary_part(from, to - from)
      |> String.replace(~r/[^\n]/, " ")

    binary_part(text, 0, from) <> blank <> binary_part(text, to, byte_size(text) - to)
  end

  # Returns `{:tag, tag}` and `{:ignored, from_byte, to_byte}` events in document order.
  defp scan_markup(text, first_line) do
    newlines =
      text
      |> :binary.matches("\n")
      |> Enum.map(&elem(&1, 0))

    text
    |> scan(0, newlines, first_line, [])
    |> Enum.reverse()
  end

  defp scan(text, pos, newlines, first_line, acc) do
    size = byte_size(text)

    case pos < size && :binary.match(text, ["<", "{"], scope: {pos, size - pos}) do
      {at, _length} -> scan_at(text, at, newlines, first_line, acc)
      _none -> acc
    end
  end

  defp scan_at(text, at, newlines, first_line, acc) do
    rest = binary_part(text, at, byte_size(text) - at)

    case skipped_markup(rest) do
      {terminator, comment?} -> skip_to(text, at, terminator, newlines, first_line, acc, comment?)
      nil -> scan_other(rest, text, at, newlines, first_line, acc)
    end
  end

  # Markup the scanner jumps over: the terminator that ends it and whether it is a comment.
  defp skipped_markup("<!--" <> _rest), do: {"-->", true}
  defp skipped_markup("<%!--" <> _rest), do: {"--%>", true}
  defp skipped_markup("<%#" <> _rest), do: {"%>", true}
  defp skipped_markup("<%" <> _rest), do: {"%>", false}
  defp skipped_markup("</" <> _rest), do: {">", false}
  defp skipped_markup("<!" <> _rest), do: {">", false}
  defp skipped_markup(_rest), do: nil

  defp scan_other("{" <> _rest, text, at, newlines, first_line, acc) do
    case skip_braces(text, at) do
      nil -> scan(text, at + 1, newlines, first_line, acc)
      stop -> scan(text, stop, newlines, first_line, acc)
    end
  end

  defp scan_other(rest, text, at, newlines, first_line, acc) do
    if Regex.match?(~r/\A<[A-Za-z.:]/, rest),
      do: scan_tag(text, at, newlines, first_line, acc),
      else: scan(text, at + 1, newlines, first_line, acc)
  end

  defp skip_to(text, at, marker, newlines, first_line, acc, ignored?) do
    stop = skip_past(text, at, marker)
    acc = if ignored?, do: [{:ignored, at, stop} | acc], else: acc
    scan(text, stop, newlines, first_line, acc)
  end

  defp scan_tag(text, at, newlines, first_line, acc) do
    rest = binary_part(text, at, byte_size(text) - at)
    [name] = Regex.run(~r/\A<([A-Za-z.:][\w.:-]*)/, rest, capture: :all_but_first)

    {attrs, stop, self_closing?} =
      scan_attrs(text, at + 1 + byte_size(name), [], newlines, first_line)

    tag = %{name: name, line: line_at(newlines, at, first_line), attrs: Enum.reverse(attrs)}
    acc = [{:tag, tag} | acc]

    if not self_closing? and ascii_downcase(name) in ["script", "style"] do
      raw_stop = raw_text_stop(text, name, stop)
      scan(text, raw_stop, newlines, first_line, [{:ignored, stop, raw_stop} | acc])
    else
      scan(text, stop, newlines, first_line, acc)
    end
  end

  defp raw_text_stop(text, name, stop) do
    text
    |> ascii_downcase()
    |> find("</" <> ascii_downcase(name), stop)
  end

  # Returns `{attrs, position_after_tag, self_closing?}`.
  defp scan_attrs(text, pos, attrs, newlines, first_line) do
    size = byte_size(text)
    pos = skip_space(text, pos)

    if pos >= size do
      {attrs, size, false}
    else
      rest = binary_part(text, pos, size - pos)
      scan_attr_token(rest, {text, pos, size}, attrs, {newlines, first_line})
    end
  end

  defp scan_attr_token("/>" <> _rest, {_text, pos, _size}, attrs, _lines),
    do: {attrs, pos + 2, true}

  defp scan_attr_token(">" <> _rest, {_text, pos, _size}, attrs, _lines),
    do: {attrs, pos + 1, false}

  defp scan_attr_token("<%" <> _rest, {text, pos, _size}, attrs, {newlines, first_line}),
    do: scan_attrs(text, skip_past(text, pos, "%>"), attrs, newlines, first_line)

  defp scan_attr_token("{" <> _rest, {text, pos, size}, attrs, {newlines, first_line}),
    do: scan_attrs(text, skip_braces(text, pos) || size, attrs, newlines, first_line)

  defp scan_attr_token(rest, {text, pos, _size}, attrs, {newlines, first_line}) do
    case Regex.run(~r/\A[^\s=\/>{"']+/, rest) do
      [name] ->
        {value, stop} = scan_value(text, pos + byte_size(name))
        attr = {name, value, line_at(newlines, pos, first_line)}
        scan_attrs(text, stop, [attr | attrs], newlines, first_line)

      nil ->
        scan_attrs(text, pos + 1, attrs, newlines, first_line)
    end
  end

  defp scan_value(text, pos) do
    size = byte_size(text)
    after_name = skip_space(text, pos)

    if after_name < size and :binary.at(text, after_name) == ?= do
      value_start = skip_space(text, after_name + 1)
      value_rest = binary_part(text, min(value_start, size), max(size - value_start, 0))
      attribute_value(value_rest, text, value_start, size)
    else
      {nil, pos}
    end
  end

  defp attribute_value(value_rest, text, value_start, size) do
    cond do
      quote = quote_char(value_rest) ->
        closing = find(text, quote, value_start + 1)
        value = binary_part(text, min(value_start + 1, size), max(closing - value_start - 1, 0))
        {{:string, value}, min(closing + 1, size)}

      String.starts_with?(value_rest, "{") ->
        stop = skip_braces(text, value_start) || size
        {{:expr, binary_part(text, value_start + 1, max(stop - value_start - 2, 0))}, stop}

      true ->
        [token] = Regex.run(~r/\A[^\s>]*/, value_rest)
        {{:bare, token}, value_start + byte_size(token)}
    end
  end

  # Byte-preserving, so offsets in the lowered copy are valid in the original.
  defp ascii_downcase(text), do: for(<<c <- text>>, into: <<>>, do: <<lower(c)>>)

  defp lower(c) when c in ?A..?Z, do: c + 32
  defp lower(c), do: c

  defp quote_char("\"" <> _rest), do: "\""
  defp quote_char("'" <> _rest), do: "'"
  defp quote_char(_rest), do: nil

  defp find(text, marker, from) do
    size = byte_size(text)

    case from < size && :binary.match(text, marker, scope: {from, size - from}) do
      {found, _length} -> found
      _none -> size
    end
  end

  defp skip_past(text, from, marker) do
    min(find(text, marker, from) + byte_size(marker), byte_size(text))
  end

  defp skip_space(text, pos) do
    size = byte_size(text)
    [spaces] = Regex.run(~r/\A\s*/, binary_part(text, min(pos, size), max(size - pos, 0)))
    pos + byte_size(spaces)
  end

  # Position just after the `}` balancing the `{` at `from`; `nil` when unbalanced. String
  # literals inside the expression may contain braces.
  defp skip_braces(text, from), do: brace_scan(text, from + 1, 1, false)

  defp brace_scan(text, pos, _depth, _in_string?) when pos >= byte_size(text), do: nil

  defp brace_scan(text, pos, depth, in_string?) do
    case :binary.at(text, pos) do
      ?\\ when in_string? -> brace_scan(text, pos + 2, depth, in_string?)
      ?" -> brace_scan(text, pos + 1, depth, not in_string?)
      ?{ when not in_string? -> brace_scan(text, pos + 1, depth + 1, in_string?)
      ?} when not in_string? and depth == 1 -> pos + 1
      ?} when not in_string? -> brace_scan(text, pos + 1, depth - 1, in_string?)
      _char -> brace_scan(text, pos + 1, depth, in_string?)
    end
  end

  defp line_at(newlines, pos, first_line), do: first_line + Enum.count(newlines, &(&1 < pos))
end
