defmodule OptimumCredo.OptimumStructureSupport do
  @moduledoc false
  # Small AST and path helpers shared by the structure, ordering and naming checks.

  @def_kinds [:def, :defp, :defmacro, :defmacrop, :defdelegate]

  @doc "Splits a filename into path segments, accepting both separators."
  @spec path_segments(String.t() | nil) :: [String.t()]
  def path_segments(nil), do: []

  def path_segments(filename) do
    filename
    |> String.replace("\\", "/")
    |> Path.split()
  end

  @doc """
  Returns `{root_segments, rest}` split at the `dir` segment that starts the project.

  When several segments are named `dir` (`/var/lib/ci/app/lib/app/x.ex`), the first one
  whose parent directory contains a `mix.exs` wins; without any such directory the first
  segment is used, which suits the project-relative paths Credo normally hands to checks.
  """
  @spec split_at_dir(String.t() | nil, String.t()) :: {[String.t()], [String.t()]} | nil
  def split_at_dir(filename, dir) do
    segments = path_segments(filename)

    candidates =
      segments
      |> Enum.with_index()
      |> Enum.filter(fn {segment, _index} -> segment == dir end)
      |> Enum.map(&elem(&1, 1))

    index =
      Enum.find(candidates, fn candidate ->
        segments
        |> Enum.take(candidate)
        |> project_root?()
      end) || List.first(candidates)

    if index do
      {root, [^dir | rest]} = Enum.split(segments, index)
      {root, rest}
    end
  end

  defp project_root?(root_segments) do
    root_segments
    |> Enum.concat(["mix.exs"])
    |> Path.join()
    |> File.regular?()
  end

  @doc """
  Whether the normalized path contains any of the given fragments.

  Fragments are substrings (either separator is accepted) or regular expressions.
  """
  @spec path_matches?(String.t() | nil, [String.t() | Regex.t()] | String.t() | Regex.t()) ::
          boolean()
  def path_matches?(filename, fragments) do
    path =
      filename
      |> path_segments()
      |> Enum.join("/")

    fragments
    |> List.wrap()
    |> Enum.any?(fn
      %Regex{} = regex ->
        Regex.match?(regex, path)

      fragment ->
        String.contains?(
          path,
          fragment
          |> to_string()
          |> String.replace("\\", "/")
        )
    end)
  end

  @doc """
  Acceptable module paths for a file path (segments without extension).

  Phoenix generators place web modules in layer directories that are not part of the
  module name (`app_web/controllers/page_controller.ex` defines `AppWeb.PageController`),
  so a `_web` directory followed by a layer directory also accepts the path without that
  layer. The `_web` directory may be the first segment or the second one below a nested
  root namespace (`my_org/my_app_web/controllers/...`).
  """
  @spec module_paths([String.t()], [String.t()]) :: [String.t()]
  def module_paths(segments, layer_dirs) do
    full = Enum.join(segments, "/")

    stripped =
      Enum.flat_map([0, 1], fn index ->
        with {:ok, web} <- Enum.fetch(segments, index),
             {:ok, layer} <- Enum.fetch(segments, index + 1),
             true <-
               String.ends_with?(web, "_web") and layer in layer_dirs and
                 length(segments) > index + 2 do
          [
            segments
            |> List.delete_at(index + 1)
            |> Enum.join("/")
          ]
        else
          _other -> []
        end
      end)

    Enum.uniq([full | stripped])
  end

  @doc "The first top-level `defmodule` of a file as `{segments, line}`, if it has a literal name."
  @spec primary_module(Macro.t()) :: {[atom()], pos_integer()} | nil
  def primary_module(ast) do
    module =
      ast
      |> statements()
      |> Enum.find_value(fn
        {:defmodule, meta, [name | _tail]} ->
          case alias_segments(name) do
            nil -> :dynamic
            segments -> {segments, meta[:line] || 1}
          end

        _other ->
          nil
      end)

    if module == :dynamic, do: nil, else: module
  end

  @doc """
  Every `defmodule` of a file with its full (parent-prefixed) name.

  Returns maps with `:segments`, `:line` and `:nested?` (defined inside another module).
  `defmodule __MODULE__.Child` inside a module is resolved against it. Modules whose name
  is not a literal alias, and everything below them, are skipped.
  """
  @spec modules(Macro.t()) :: [%{segments: [atom()], line: pos_integer(), nested?: boolean()}]
  def modules(ast) do
    ast
    |> statements()
    |> collect_modules([], false)
  end

  defp collect_modules(statements, parent, nested?) do
    Enum.flat_map(statements, fn
      {:defmodule, meta, [name, [do: body]]} ->
        case module_name(name, parent) do
          nil ->
            []

          full ->
            nested =
              body
              |> statements()
              |> collect_modules(full, true)

            [%{segments: full, line: meta[:line] || 1, nested?: nested?}] ++ nested
        end

      _other ->
        []
    end)
  end

  # `defmodule __MODULE__.Child` is relative to the enclosing module.
  defp module_name({:__aliases__, _meta, [{:__MODULE__, _meta2, context} | rest]}, parent)
       when is_atom(context) and parent != [] do
    if Enum.all?(rest, &is_atom/1), do: parent ++ rest
  end

  defp module_name(name, parent) do
    case alias_segments(name) do
      [:"Elixir" | absolute] -> absolute
      nil -> nil
      relative -> parent ++ relative
    end
  end

  @doc "Statements of a `do` body, whether it is a block or a single expression."
  @spec statements(Macro.t()) :: [Macro.t()]
  def statements({:__block__, _meta, statements}), do: statements
  def statements(nil), do: []
  def statements(statement), do: [statement]

  @doc "Module name segments for a literal alias, or `nil` for anything dynamic."
  @spec alias_segments(Macro.t()) :: [atom()] | nil
  def alias_segments({:__aliases__, _meta, segments}) do
    if Enum.all?(segments, &is_atom/1), do: segments
  end

  def alias_segments(_other), do: nil

  @doc "Extracts the literal name of a function definition head."
  @spec head_name(Macro.t()) :: atom() | nil
  def head_name({:when, _meta, [head | _guards]}), do: head_name(head)
  def head_name({name, _meta, args}) when is_atom(name) and is_list(args), do: name
  def head_name({name, _meta, context}) when is_atom(name) and is_atom(context), do: name
  def head_name(_other), do: nil

  @doc "Arguments of a function definition head."
  @spec head_args(Macro.t()) :: [Macro.t()]
  def head_args({:when, _meta, [head | _guards]}), do: head_args(head)
  def head_args({_name, _meta, args}) when is_list(args), do: args
  def head_args(_other), do: []

  @doc """
  Lists the function clauses of a module body in source order.

  Each clause is a map with `:kind`, `:name`, `:args`, `:arity`, `:arities`, `:body`,
  `:body?`, `:extra_blocks?`, `:code`, `:line` and `:impl?`.

  `:arity` is the head's argument count and `:arities` the range of arities it defines
  (default arguments `\\\\` add lower arities). `:body` is the `do` block, `:body?` tells a
  `do: nil` body from a bodiless head, and `:extra_blocks?` is true for `rescue`, `catch`,
  `else` and `after` blocks. `:code` lists everything executed by the clause (guards and
  all blocks) for call scanning.

  A clause is `impl?` when a preceding `@impl` (other than `@impl false`) applies to its
  name and arity; the `@impl` applies to every following clause of the same function.
  """
  @spec functions([Macro.t()]) :: [map()]
  def functions(statements) do
    {clauses, _state} =
      Enum.flat_map_reduce(statements, {false, MapSet.new()}, &function_clause/2)

    Enum.reject(clauses, &is_nil(&1.name))
  end

  defp function_clause({:@, _meta, [{:impl, _impl_meta, [value]}]}, {_pending, functions}),
    do: {[], {value != false, functions}}

  defp function_clause({kind, meta, [head | rest]}, {pending, functions})
       when kind in @def_kinds do
    name = head_name(head)
    args = head_args(head)
    arity = length(args)
    impl? = pending or MapSet.member?(functions, {name, arity})
    functions = if pending, do: MapSet.put(functions, {name, arity}), else: functions

    clause =
      rest
      |> clause_options()
      |> build_clause(kind, meta, head)
      |> Map.merge(%{name: name, args: args, arity: arity, impl?: impl?})

    {[clause], {false, functions}}
  end

  defp function_clause(_other, state), do: {[], state}

  defp build_clause(options, kind, meta, head) do
    args = head_args(head)
    arity = length(args)

    %{
      kind: kind,
      arities: (arity - default_count(args))..arity//1,
      body: Keyword.get(options, :do),
      body?: Keyword.has_key?(options, :do),
      extra_blocks?: Keyword.has_key?(options, :do) and Keyword.keys(options) != [:do],
      code: [guards(head) | Keyword.values(options)],
      line: meta[:line] || 1
    }
  end

  defp clause_options([options | _tail]) when is_list(options) do
    if Keyword.keyword?(options), do: options, else: []
  end

  defp clause_options(_other), do: []

  defp default_count(args), do: Enum.count(args, &match?({:\\, _meta, _args}, &1))

  defp guards({:when, _meta, [_head | guards]}), do: guards
  defp guards(_head), do: []

  @doc """
  Local calls `{name, arity}` made by an AST, as a `MapSet`.

  Pipelines count the piped value as an argument, `&name/arity` captures count with their
  written arity, and `quote` blocks are skipped because they expand in another module.
  """
  @spec local_calls(Macro.t()) :: MapSet.t({atom(), non_neg_integer()})
  def local_calls(ast) do
    ast
    |> collect_calls([])
    |> MapSet.new()
  end

  defp collect_calls({:quote, _meta, _args}, acc), do: acc

  defp collect_calls({:&, _meta, [{:/, _meta2, [{name, _tuple_meta, context}, arity]}]}, acc)
       when is_atom(name) and is_atom(context) and is_integer(arity),
       do: [{name, arity} | acc]

  defp collect_calls({:|>, _meta, [left, right]}, acc) do
    acc = collect_calls(left, acc)

    case right do
      {name, _meta, args} when is_atom(name) and is_list(args) ->
        collect_calls(args, [{name, length(args) + 1} | acc])

      other ->
        collect_calls(other, acc)
    end
  end

  defp collect_calls({name, _meta, args}, acc) when is_atom(name) and is_list(args),
    do: collect_calls(args, [{name, length(args)} | acc])

  defp collect_calls({head, _meta, args}, acc) when is_list(args),
    do: collect_calls(args, collect_calls(head, acc))

  defp collect_calls({left, right}, acc), do: collect_calls(right, collect_calls(left, acc))
  defp collect_calls(list, acc) when is_list(list), do: Enum.reduce(list, acc, &collect_calls/2)
  defp collect_calls(_other, acc), do: acc

  @doc """
  Splits statements into runs of consecutive statements that `classifier` accepts.

  The classifier returns `{key, line}` for an ordered statement or `nil`, which ends
  the current run. Runs shorter than `min_run` are dropped.
  """
  @spec runs([Macro.t()], (Macro.t() -> {term(), pos_integer()} | nil), pos_integer()) :: [
          [{term(), pos_integer()}]
        ]
  def runs(statements, classifier, min_run) do
    statements
    |> Enum.chunk_while(
      [],
      fn statement, run ->
        case classifier.(statement) do
          nil -> {:cont, Enum.reverse(run), []}
          entry -> {:cont, [entry | run]}
        end
      end,
      fn run -> {:cont, Enum.reverse(run), []} end
    )
    |> Enum.filter(&(length(&1) >= min_run))
  end

  @doc """
  Finds the first entry that sorts before its predecessor.

  Entries are `{sort_key, line}` pairs.
  """
  @spec first_unsorted([{term(), pos_integer()}]) ::
          {previous :: term(), current :: term(), pos_integer()} | nil
  def first_unsorted(entries) do
    entries
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.find_value(fn [{previous, _value}, {current, line}] ->
      if current < previous, do: {previous, current, line}
    end)
  end

  @doc "Normalizes a configured list of atoms or strings into strings."
  @spec to_strings(term()) :: [String.t()]
  def to_strings(values) do
    values
    |> List.wrap()
    |> Enum.flat_map(fn
      value when is_atom(value) and not is_nil(value) -> [Atom.to_string(value)]
      value when is_binary(value) -> [value]
      _other -> []
    end)
  end

  @doc "Literal atoms or strings of a list AST, if every element is the same literal kind."
  @spec literal_names(Macro.t()) :: [{String.t(), pos_integer()}] | nil
  def literal_names(list) when is_list(list) and list != [] do
    cond do
      Enum.all?(list, &name_atom?/1) ->
        Enum.map(list, &{Atom.to_string(&1), 0})

      Enum.all?(list, &is_binary/1) ->
        Enum.map(list, &{&1, 0})

      true ->
        nil
    end
  end

  def literal_names(_other), do: nil

  defp name_atom?(value), do: is_atom(value) and not is_boolean(value) and not is_nil(value)
end
