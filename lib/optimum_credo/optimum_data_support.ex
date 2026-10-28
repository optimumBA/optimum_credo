defmodule OptimumCredo.OptimumDataSupport do
  @moduledoc false
  # Shared helpers for the data, migration, configuration and Ash heuristics.
  # Every function is static: nothing here executes user code or resolves aliases.

  @type call ::
          {module :: [atom()] | atom(), function :: atom(), args :: list(), meta :: keyword()}

  @doc """
  The file path with a leading `/` and, for absolute paths below the working directory,
  made relative to it. Directory checks like `test/` then do not match an ancestor of the
  project (`/home/me/test/app/lib/x.ex`).
  """
  @spec normalized_path(Credo.SourceFile.t()) :: String.t()
  def normalized_path(%Credo.SourceFile{filename: filename}) do
    path = String.replace(filename || "", "\\", "/")

    relative =
      path
      |> relative_to_cwd()
      |> String.trim_leading("/")

    "/" <> relative
  end

  defp relative_to_cwd(path) do
    case File.cwd() do
      {:ok, cwd} ->
        cwd =
          cwd
          |> String.replace("\\", "/")
          |> String.trim_trailing("/")

        if String.starts_with?(path, cwd <> "/"),
          do: String.replace_prefix(path, cwd, ""),
          else: path

      _error ->
        path
    end
  end

  @spec in_dir?(Credo.SourceFile.t(), String.t()) :: boolean()
  def in_dir?(source_file, dir) do
    source_file
    |> normalized_path()
    |> String.contains?("/" <> dir)
  end

  @spec ends_with_path?(Credo.SourceFile.t(), String.t()) :: boolean()
  def ends_with_path?(source_file, suffix) do
    source_file
    |> normalized_path()
    |> String.ends_with?("/" <> suffix)
  end

  @spec migration?(Credo.SourceFile.t()) :: boolean()
  def migration?(source_file),
    do: Regex.match?(~r{/priv/[^/]+/migrations/}, normalized_path(source_file))

  @spec ignored_file?(Credo.SourceFile.t(), term()) :: boolean()
  def ignored_file?(source_file, patterns) do
    path = normalized_path(source_file)

    patterns
    |> List.wrap()
    |> Enum.any?(fn
      %Regex{} = regex ->
        Regex.match?(regex, path)

      pattern when is_binary(pattern) ->
        String.ends_with?(path, "/" <> String.trim_leading(pattern, "/"))

      _other ->
        false
    end)
  end

  @doc "Whether any of `dirs` (like `\"test/\"`) is a directory in the file path."
  @spec in_any_dir?(Credo.SourceFile.t(), [String.t()]) :: boolean()
  def in_any_dir?(source_file, dirs), do: Enum.any?(dirs, &in_dir?(source_file, &1))

  @doc "All remote calls in `ast`, including the arity-less `&Mod.fun/1` capture target."
  @spec remote_calls(Macro.t()) :: [call()]
  def remote_calls(ast) do
    {_ast, calls} =
      Macro.prewalk(ast, [], fn node, acc ->
        case remote_call(node) do
          nil -> {node, acc}
          call -> {node, [call | acc]}
        end
      end)

    Enum.reverse(calls)
  end

  @spec remote_call(Macro.t()) :: call() | nil
  def remote_call({{:., _dot_meta, [module, function]}, meta, args})
      when is_atom(function) and is_list(args) do
    case module_key(module) do
      nil -> nil
      key -> {key, function, args, meta}
    end
  end

  def remote_call(_node), do: nil

  defp module_key({:__aliases__, _meta, [first | _tail] = segments}) when is_atom(first),
    do: if(Enum.all?(segments, &is_atom/1), do: segments)

  defp module_key(module)
       when is_atom(module) and not is_nil(module) and module not in [true, false],
       do: module

  defp module_key(_other), do: nil

  @doc """
  Rewrites every `__aliases__` node whose first segment was introduced by an `alias` into
  the full module, following lexical scope: an alias is visible to the statements after it
  in the same block and in nested modules, and does not leak out of a `defmodule` or a
  function body. Handles `alias A.B`, `alias A.B, as: C` and `alias A.{B, C.D}`.

  A rewritten node keeps its line and gets `alias_written: n` in its metadata, `n` being the
  number of segments written in the source (`1` for `User` after `alias MyApp.Accounts.User`).
  """
  @spec expand_aliases(Macro.t()) :: Macro.t()
  def expand_aliases(ast) do
    ast
    |> expand(%{})
    |> elem(0)
  end

  defp expand({:defmodule, meta, [name, body]}, env) do
    {name, _env} = expand(name, env)
    {body, _env} = expand(body, env)
    {{:defmodule, meta, [name, body]}, env}
  end

  defp expand({:__block__, meta, statements}, env) when is_list(statements) do
    {statements, _env} =
      Enum.map_reduce(statements, env, &expand/2)

    {{:__block__, meta, statements}, env}
  end

  defp expand({:alias, _meta, _args} = node, env), do: {node, define_aliases(node, env)}

  defp expand({:__aliases__, meta, [first | rest] = segments} = node, env) when is_atom(first) do
    case env do
      %{^first => target} ->
        {{:__aliases__, Keyword.put(meta, :alias_written, length(segments)), target ++ rest}, env}

      _env ->
        {node, env}
    end
  end

  defp expand({form, meta, args}, env) when is_list(args) do
    {form, _env} = expand(form, env)
    {args, _env} = expand(args, env)
    {{form, meta, args}, env}
  end

  defp expand({left, right}, env) do
    {left, _env} = expand(left, env)
    {right, _env} = expand(right, env)
    {{left, right}, env}
  end

  defp expand(list, env) when is_list(list) do
    expanded = Enum.map(list, fn element -> elem(expand(element, env), 0) end)
    {expanded, env}
  end

  defp expand(other, env), do: {other, env}

  # `alias` statements are expanded against the aliases defined before them.
  defp define_aliases({:alias, _meta, [target | options]}, env) do
    {target, _env} = expand_target(target, env)
    put_aliases(target, alias_name(options), env)
  end

  defp define_aliases(_statement, env), do: env

  defp alias_name(options) do
    with [options] <- options,
         true <- Keyword.keyword?(options),
         {:__aliases__, _meta, [name]} when is_atom(name) <- Keyword.get(options, :as) do
      name
    else
      _other -> nil
    end
  end

  defp put_aliases({:__aliases__, _meta, segments}, as, env) when is_list(segments) do
    if Enum.all?(segments, &is_atom/1),
      do: Map.put(env, as || List.last(segments), segments),
      else: env
  end

  defp put_aliases({:multi, base, children}, _as, env),
    do: Enum.reduce(children, env, &put_child_alias(&1, &2, base))

  defp put_aliases(_other, _as, env), do: env

  defp put_child_alias({:__aliases__, _meta, rest}, acc, base) when is_list(rest) do
    if Enum.all?(rest, &is_atom/1),
      do: Map.put(acc, List.last(rest), base ++ rest),
      else: acc
  end

  defp put_child_alias(_other, acc, _base), do: acc

  defp expand_target(
         {{:., _meta, [{:__aliases__, _alias_meta, base}, :{}]}, _tuple_meta, children},
         env
       )
       when is_list(base) and is_list(children) do
    case expand({:__aliases__, [], base}, env) do
      {{:__aliases__, _meta, base}, env} -> {{:multi, base, children}, env}
    end
  end

  defp expand_target(target, env), do: expand(target, env)

  @doc "Last alias segment of a module AST, e.g. `Repo` for `MyApp.Repo`."
  @spec last_segment(Macro.t()) :: atom() | nil
  def last_segment({:__aliases__, _meta, segments}) when is_list(segments) do
    if Enum.all?(segments, &is_atom/1), do: List.last(segments)
  end

  def last_segment(_other), do: nil

  @spec line(keyword()) :: pos_integer()
  def line(meta), do: meta[:line] || 1

  @doc "Returns the keyword list literal found among call arguments, if any."
  @spec keyword_arg(list()) :: keyword() | nil
  def keyword_arg(args) do
    args
    |> List.wrap()
    |> Enum.find(&keyword_literal?/1)
  end

  @spec keyword_literal?(term()) :: boolean()
  def keyword_literal?([_head | _tail] = list),
    do: Enum.all?(list, &match?({key, _} when is_atom(key), &1))

  def keyword_literal?(_other), do: false

  @doc """
  Looks up `key` in the keyword literals among `args`. Returns `{:ok, value}` or `:error`.
  """
  @spec fetch_option(list(), atom()) :: {:ok, Macro.t()} | :error
  def fetch_option(args, key) do
    args
    |> List.wrap()
    |> Enum.filter(&keyword_literal?/1)
    |> Enum.find_value(:error, fn options ->
      case List.keyfind(options, key, 0) do
        {^key, value} -> {:ok, value}
        nil -> nil
      end
    end)
  end

  @doc "Static string value of a literal, heredoc, `~s`/`~S` sigil or interpolated string."
  @spec string_value(Macro.t()) :: String.t() | nil
  def string_value(value) when is_binary(value), do: value

  def string_value({:<<>>, _meta, parts}) do
    Enum.map_join(parts, fn
      part when is_binary(part) -> part
      _interpolation -> "\0"
    end)
  end

  def string_value({sigil, _meta, [{:<<>>, _meta2, _args} = body, _modifiers]})
      when sigil in [:sigil_s, :sigil_S],
      do: string_value(body)

  def string_value(_other), do: nil

  @doc """
  Returns the nodes matching `match?` that are not inside a branch guarded by `guard?`.

  A node is guarded when it sits in a later argument of `if`/`unless`/`case`/`with`, on the
  right of `||`/`&&`/`and`/`or`, or on the right side of a pipe, and `guard?` accepts the
  condition (the first argument, the left operand, or any `with` clause).
  """
  @spec unguarded_nodes(Macro.t(), (Macro.t() -> boolean()), (Macro.t() -> boolean())) :: [
          Macro.t()
        ]
  def unguarded_nodes(ast, guard?, match?), do: collect(ast, guard?, match?, false)

  defp collect({:with, _meta, args}, guard?, match?, guarded) when is_list(args) do
    guarded_body? = guarded or Enum.any?(args, &contains?(&1, guard?))

    own(match?, {:with, [], args}, guarded) ++
      Enum.flat_map(args, &collect(&1, guard?, match?, guarded_body?))
  end

  defp collect({operator, _meta, [condition | rest]} = node, guard?, match?, guarded)
       when operator in [:if, :unless, :case, :||, :&&, :and, :or, :|>] do
    guarded_rest? = guarded or contains?(condition, guard?)

    own(match?, node, guarded) ++
      collect(condition, guard?, match?, guarded) ++
      Enum.flat_map(rest, &collect(&1, guard?, match?, guarded_rest?))
  end

  defp collect({form, _meta, args} = node, guard?, match?, guarded) do
    own(match?, node, guarded) ++
      collect(form, guard?, match?, guarded) ++
      if(is_list(args), do: Enum.flat_map(args, &collect(&1, guard?, match?, guarded)), else: [])
  end

  defp collect({left, right}, guard?, match?, guarded),
    do: collect(left, guard?, match?, guarded) ++ collect(right, guard?, match?, guarded)

  defp collect(list, guard?, match?, guarded) when is_list(list),
    do: Enum.flat_map(list, &collect(&1, guard?, match?, guarded))

  defp collect(_other, _guard?, _match?, _guarded), do: []

  defp own(_match?, _node, true), do: []
  defp own(match?, node, false), do: if(match?.(node), do: [node], else: [])

  @doc "Whether any node in `ast` satisfies `predicate`."
  @spec contains?(Macro.t(), (Macro.t() -> boolean())) :: boolean()
  def contains?(ast, predicate) do
    {_ast, found?} =
      Macro.prewalk(ast, false, fn node, found? -> {node, found? or predicate.(node)} end)

    found?
  end

  @doc """
  Source lines that carry a comment, as a `MapSet` of line numbers. Strings, heredocs
  and sigils are blanked first so `#` characters inside them are not counted.
  """
  @spec comment_lines(Credo.SourceFile.t()) :: MapSet.t(pos_integer())
  def comment_lines(source_file) do
    source_file
    |> code_and_comment_lines()
    |> Enum.flat_map(fn {line_no, _code, comment} -> if comment, do: [line_no], else: [] end)
    |> MapSet.new()
  end

  @doc "Lines as `{line_no, code, comment_or_nil}` with strings/sigils blanked."
  @spec code_and_comment_lines(Credo.SourceFile.t()) :: [
          {pos_integer(), String.t(), String.t() | nil}
        ]
  def code_and_comment_lines(source_file) do
    # Credo 1.7's string cleaner can fail on a closing quote at EOF. Preserve line counts
    # by removing exactly the newline added for its scanner.
    source = Credo.SourceFile.source(source_file) <> "\n"

    source
    |> Credo.Code.clean_charlists_strings_and_sigils()
    |> String.replace_suffix("\n", "")
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.map(fn {text, line_no} ->
      case Regex.run(~r/(?<![?\\])#/, text, return: :index) do
        [{index, _length}] ->
          {line_no, binary_part(text, 0, index),
           binary_part(text, index, byte_size(text) - index)}

        nil ->
          {line_no, text, nil}
      end
    end)
  end

  @doc """
  The module AST bodies of every `defmodule`, innermost included, as `{name_ast, body}`.
  Modules written inside a `quote` block are templates, not modules of this file, and are
  skipped.
  """
  @spec modules(Macro.t()) :: [{Macro.t(), Macro.t()}]
  def modules(ast) do
    {_ast, modules} =
      Macro.prewalk(ast, [], fn
        {:quote, _meta, _args}, acc -> {nil, acc}
        {:defmodule, _meta, [name, [do: body]]} = node, acc -> {node, [{name, body} | acc]}
        node, acc -> {node, acc}
      end)

    Enum.reverse(modules)
  end

  @doc """
  A module body without the code that belongs to another scope: nested `defmodule`s and
  `quote` blocks are removed.
  """
  @spec lexical_body(Macro.t()) :: Macro.t()
  def lexical_body(body) do
    Macro.prewalk(body, fn
      {:defmodule, _meta, _args} -> nil
      {:quote, _meta, _args} -> nil
      node -> node
    end)
  end

  @doc "Statements of a `do` body."
  @spec statements(Macro.t()) :: [Macro.t()]
  def statements({:__block__, _meta, statements}), do: statements
  def statements(nil), do: []
  def statements(statement), do: [statement]
end
