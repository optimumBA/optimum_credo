defmodule OptimumCredo.TestsSupport do
  @moduledoc false

  # Small AST and path helpers shared by the test-suite heuristics. Everything here is
  # static: it reads literal AST and never resolves aliases, imports or macros.

  alias Credo.SourceFile

  @type test_block :: %{
          kind: :test | :describe,
          name: Macro.t(),
          line: pos_integer(),
          args: [Macro.t()],
          body: Macro.t(),
          env: env()
        }

  @doc "True for `*_test.exs` files and `.exs` files under a `test` directory."
  @spec test_file?(SourceFile.t()) :: boolean()
  def test_file?(%SourceFile{filename: filename}) do
    path = normalize_path(filename)

    String.ends_with?(path, "_test.exs") or
      (String.ends_with?(path, ".exs") and "test" in Path.split(path))
  end

  @doc "Substring match against the `/`-normalized file name."
  @spec path_matches?(SourceFile.t(), [String.t()]) :: boolean()
  def path_matches?(%SourceFile{filename: filename}, fragments) do
    path = normalize_path(filename)

    fragments
    |> List.wrap()
    |> Enum.any?(&String.contains?(path, &1))
  end

  defp normalize_path(filename), do: String.replace(filename, "\\", "/")

  @doc "Parsed AST of the source file."
  @spec ast(SourceFile.t()) :: Macro.t()
  def ast(%SourceFile{} = source_file), do: SourceFile.ast(source_file)

  # Modules are identified by name, never by atom: names come from the analyzed source or from
  # configuration, and turning arbitrary names into atoms is unbounded. An Elixir module is its
  # dotted name without the `Elixir.` prefix (`"Enum"`); an Erlang module keeps its colon
  # (`":rand"`).
  @type module_name :: String.t()

  @type env :: %{
          aliases: %{optional(atom()) => module_name() | :unknown},
          imports: [import_spec()]
        }
  @type import_spec :: %{
          module: module_name(),
          only: nil | :functions | :macros | [{atom(), non_neg_integer() | nil}],
          except: [{atom(), non_neg_integer() | nil}]
        }

  @type call :: %{
          kind: :remote | :local,
          module: module_name() | nil,
          fun: atom(),
          args: [Macro.t()],
          meta: keyword()
        }

  @non_calls [
    :.,
    :__aliases__,
    :__block__,
    :{},
    :%{},
    :%,
    :<<>>,
    :fn,
    :&,
    :=,
    :->,
    :"::",
    :|,
    :quote,
    :unquote,
    :unquote_splicing,
    :^,
    :__MODULE__
  ]

  @doc "An environment without aliases or imports."
  @spec new_env() :: env()
  def new_env, do: %{aliases: %{}, imports: []}

  @doc """
  Pre-order walk that does not descend into `quote` blocks.

  `fun` receives each node and the accumulator and returns the new accumulator.
  """
  @spec walk(Macro.t(), acc, (Macro.t(), acc -> acc)) :: acc when acc: term()
  def walk(ast, acc, fun) do
    walk_env(ast, acc, fn node, _env, acc -> {:cont, fun.(node, acc)} end)
  end

  @doc """
  Pre-order walk that tracks lexical `alias`/`import`/`require` scope.

  `fun` receives `(node, env, acc)` and returns `{:cont, acc}` to descend or `{:skip, acc}`
  to ignore the node's children. Directives apply to the following statements of the
  enclosing block only, so an alias inside one `defmodule`, `describe` or `test` never
  leaks into a sibling. `quote` blocks are not entered.
  """
  @spec walk_env(Macro.t(), acc, (Macro.t(), env(), acc -> {:cont | :skip, acc}), env()) :: acc
        when acc: term()
  def walk_env(ast, acc, fun, env \\ new_env()) do
    {_env, acc} = visit(ast, env, acc, fun)
    acc
  end

  defp visit({:quote, _meta, _args}, env, acc, _fun), do: {env, acc}

  defp visit(node, env, acc, fun) do
    case fun.(node, env, acc) do
      {:skip, acc} -> {update_env(node, env), acc}
      {:cont, acc} -> descend(node, env, acc, fun)
    end
  end

  defp descend({:__block__, _meta, statements}, env, acc, fun) when is_list(statements) do
    {_env, acc} =
      Enum.reduce(statements, {env, acc}, fn statement, {env, acc} ->
        visit(statement, env, acc, fun)
      end)

    {env, acc}
  end

  defp descend({form, _meta, args} = node, env, acc, fun) when is_list(args) do
    children = if is_tuple(form), do: [form | args], else: args
    {update_env(node, env), visit_all(children, env, acc, fun)}
  end

  defp descend({left, right}, env, acc, fun), do: {env, visit_all([left, right], env, acc, fun)}
  defp descend(list, env, acc, fun) when is_list(list), do: {env, visit_all(list, env, acc, fun)}
  defp descend(_leaf, env, acc, _fun), do: {env, acc}

  defp visit_all(nodes, env, acc, fun) do
    Enum.reduce(nodes, acc, fn node, acc ->
      {_env, acc} = visit(node, env, acc, fun)
      acc
    end)
  end

  defp update_env({directive, _meta, [target | options]}, env)
       when directive in [:alias, :import, :require] do
    options =
      options
      |> List.first()
      |> keyword_options()

    apply_directive(directive, target, options, env)
  end

  defp update_env(_node, env), do: env

  defp apply_directive(:alias, {{:., _meta, [prefix, :{}]}, _tuple_meta, entries}, _options, env) do
    base = resolve_module(prefix, env)
    Enum.reduce(entries, env, &put_grouped_alias(&1, &2, base))
  end

  defp apply_directive(:import, target, options, env) do
    case resolve_module(target, env) do
      nil -> env
      module -> %{env | imports: [import_spec(module, options) | env.imports]}
    end
  end

  defp apply_directive(directive, target, options, env) do
    module = resolve_module(target, env)
    put_named_alias(options[:as], directive, {target, module}, env)
  end

  defp put_named_alias({:__aliases__, _meta, [name]}, _directive, {_target, module}, env),
    do: put_alias(env, name, module)

  defp put_named_alias(_ignored, :alias, {target, module}, env),
    do: put_alias(env, default_alias_name(target), module)

  defp put_named_alias(_other, _directive, _resolved, env), do: env

  defp put_grouped_alias({:__aliases__, _meta, segments}, env, base) when is_list(segments) do
    module =
      if base && Enum.all?(segments, &is_atom/1), do: join_name([base | segments])

    put_alias(env, List.last(segments), module)
  end

  defp put_grouped_alias(_other, env, _base), do: env

  defp put_alias(env, name, module) when is_atom(name),
    do: %{env | aliases: Map.put(env.aliases, name, module || :unknown)}

  defp put_alias(env, _name, _module), do: env

  defp default_alias_name({:__aliases__, _meta, segments}) when is_list(segments) do
    case List.last(segments) do
      name when is_atom(name) -> name
      _other -> nil
    end
  end

  defp default_alias_name(_target), do: nil

  defp keyword_options(options) do
    options = unwrap_literals(options)
    if is_list(options) and Keyword.keyword?(options), do: options, else: []
  end

  # Literal-encoded ASTs (see `literal_ast/1`) wrap scalars, lists and pairs in `__block__`s.
  defp unwrap_literals(ast) do
    Macro.prewalk(ast, fn
      {:__block__, _meta, [value]}
      when is_atom(value) or is_number(value) or is_binary(value) or is_list(value) or
             (is_tuple(value) and tuple_size(value) == 2) ->
        value

      node ->
        node
    end)
  end

  defp import_spec(module, options) do
    %{module: module, only: only_option(options[:only]), except: function_list(options[:except])}
  end

  defp only_option(only) when only in [:functions, :macros], do: only
  defp only_option(nil), do: nil
  defp only_option(list), do: function_list(list)

  defp function_list(list) when is_list(list) do
    for {name, arity} <- list, is_atom(name), do: {name, if(is_integer(arity), do: arity)}
  end

  defp function_list(_other), do: []

  @doc """
  Resolves an alias AST (or erlang atom) to a module name using the lexical `env`.

  Returns `nil` for anything dynamic (`__MODULE__`, variables, interpolated aliases).
  """
  @spec resolve_module(Macro.t(), env()) :: module_name() | nil
  def resolve_module({:__aliases__, _meta, [first | rest] = segments}, env) do
    cond do
      not Enum.all?(segments, &is_atom/1) ->
        nil

      Map.get(env.aliases, first) == :unknown ->
        nil

      Map.has_key?(env.aliases, first) ->
        join_name([Map.fetch!(env.aliases, first) | rest])

      true ->
        join_name(segments)
    end
  end

  def resolve_module(atom, _env) when is_atom(atom) and atom not in [nil, true, false],
    do: atom_name(atom)

  def resolve_module(_ast, _env), do: nil

  @doc "Module name of alias segments (`[:MyApp, :Repo]` becomes `\"MyApp.Repo\"`)."
  @spec join_name([atom() | String.t()]) :: module_name()
  def join_name(parts) do
    parts
    |> Enum.map(&to_string/1)
    |> drop_elixir_prefix()
    |> Enum.join(".")
  end

  defp drop_elixir_prefix(["Elixir" | [_head | _tail] = rest]), do: rest
  defp drop_elixir_prefix(parts), do: parts

  defp atom_name(atom) do
    case Atom.to_string(atom) do
      "Elixir." <> name -> name
      name -> ":" <> name
    end
  end

  @doc """
  Normalises a call node to `%{kind, module, fun, args, meta}`.

  Remote calls resolve their receiver through aliases; `apply(Mod, :fun, args)` with
  literal module and function is treated as `Mod.fun(...)`. A local call whose name is
  provided by an `import` in scope resolves to that module (`kind: :local`).
  Returns `nil` for anything that is not a plain call.
  """
  @spec call(Macro.t(), env()) :: call() | nil
  def call({{:., _dot, [receiver, fun]}, meta, args}, env) when is_atom(fun) and is_list(args) do
    module = resolve_module(receiver, env)

    if module == "Kernel" and fun == :apply do
      apply_call(args, meta, env)
    else
      %{kind: :remote, module: module, fun: fun, args: args, meta: meta}
    end
  end

  def call({:apply, meta, [_mod, _fun, _args] = args}, env) do
    apply_call(args, meta, env) || local_call(:apply, args, meta, env)
  end

  def call({name, meta, args}, env)
      when is_atom(name) and is_list(args) and name not in @non_calls do
    local_call(name, args, meta, env)
  end

  def call(_node, _env), do: nil

  defp apply_call([module_ast, fun_ast, list], meta, env) do
    with module when module != nil <- resolve_module(module_ast, env),
         {:ok, fun, _line} <- literal(fun_ast),
         true <- is_atom(fun) do
      args = if is_list(list), do: list, else: []
      %{kind: :remote, module: module, fun: fun, args: args, meta: meta}
    else
      _other -> nil
    end
  end

  defp apply_call(_args, _meta, _env), do: nil

  defp local_call(name, args, meta, env) do
    module =
      Enum.find_value(env.imports, fn spec ->
        if provides?(spec, name, [length(args), length(args) + 1]), do: spec.module
      end)

    %{kind: :local, module: module, fun: name, args: args, meta: meta}
  end

  @doc """
  Does an `import` provide `name` for one of `arities`?

  With an `only:` list this is exact. Otherwise an existing module or its installed BEAM exports are inspected. Modules
  without available compiled exports provide only the names in `assumed`.
  """
  @spec provides?(import_spec(), atom(), [non_neg_integer()], [atom()]) :: boolean()
  def provides?(spec, name, arities, assumed \\ []) do
    cond do
      listed?(spec.except, name, arities) -> false
      is_list(spec.only) -> listed?(spec.only, name, arities)
      true -> imported_export?(spec.module, name, arities, assumed)
    end
  end

  defp listed?(functions, name, arities) do
    Enum.any?(functions, fn {n, a} -> n == name and (a == nil or a in arities) end)
  end

  defp imported_export?(module_name, name, arities, assumed) do
    case existing_module(module_name) do
      {:ok, module} ->
        if :code.is_loaded(module) == false do
          installed_export?(module_name, name, arities, assumed)
        else
          exported?(module, name, arities)
        end

      :error ->
        installed_export?(module_name, name, arities, assumed)
    end
  end

  # Read installed compiled metadata without creating atoms from arbitrary source names.
  # Unlike loading the module, reading its exports does not run @on_load callbacks.
  defp installed_export?(module_name, name, arities, assumed) do
    case installed_exports(module_name) do
      {:ok, exports} -> Enum.any?(exports, &matching_export?(&1, name, arities))
      :unavailable -> name in assumed
    end
  end

  # One code-path search and BEAM read per module name and check worker process.
  # Its code path and installed dependencies remain fixed during that analysis.
  defp installed_exports(module_name) do
    key = {__MODULE__, :installed_exports, module_name}

    case Process.get(key) do
      nil ->
        exports = read_installed_exports(module_name)
        Process.put(key, exports)
        exports

      exports ->
        exports
    end
  end

  defp read_installed_exports(module_name) do
    filename =
      module_name
      |> beam_filename()
      |> String.to_charlist()

    with false <- String.contains?(module_name, ["/", "\\"]),
         path when is_list(path) <- :code.where_is_file(filename),
         {:ok, contents} <- :file.read_file(path),
         {:ok, {_module, chunks}} <- :beam_lib.chunks(contents, [:exports]) do
      {:ok, chunks[:exports]}
    else
      _unavailable -> :unavailable
    end
  end

  defp beam_filename(":" <> name), do: name <> ".beam"
  defp beam_filename(name), do: "Elixir." <> name <> ".beam"

  defp matching_export?({export, arity}, name, arities) do
    (export == name and arity in arities) or
      (Atom.to_string(export) == "MACRO-" <> Atom.to_string(name) and (arity - 1) in arities)
  end

  defp exported?(module, name, arities) do
    Enum.any?(arities, fn arity ->
      function_exported?(module, name, arity) or macro_exported?(module, name, arity)
    end)
  end

  # Unknown source names remain strings; installed BEAM metadata is inspected separately.
  defp existing_module(":" <> erlang), do: existing_atom(erlang)
  defp existing_module(name), do: existing_atom("Elixir." <> name)

  defp existing_atom(string) do
    {:ok, String.to_existing_atom(string)}
  rescue
    ArgumentError -> :error
  end

  @doc "Scalar literal value of a node (also when wrapped by a literal-encoding parse)."
  @spec literal(Macro.t()) :: {:ok, term(), pos_integer() | nil} | :error
  def literal({:__block__, meta, [value]})
      when is_binary(value) or is_number(value) or is_atom(value),
      do: {:ok, value, meta[:line]}

  def literal(value) when is_binary(value) or is_number(value) or is_atom(value),
    do: {:ok, value, nil}

  def literal(_node), do: :error

  @doc "AST with every scalar literal wrapped as `{:__block__, meta, [value]}` (carries line numbers)."
  @spec literal_ast(SourceFile.t()) :: Macro.t() | nil
  def literal_ast(%SourceFile{} = source_file) do
    case source_file
         |> SourceFile.source()
         |> Code.string_to_quoted(
           columns: true,
           token_metadata: true,
           literal_encoder: &{:ok, {:__block__, &2, [&1]}}
         ) do
      {:ok, ast} -> ast
      _error -> nil
    end
  end

  @doc """
  Finds `test`/`describe` calls with a `do` block, each with the lexical `env` it sits in.

  The name may be any expression; use `name_text/1` for the literal part.
  """
  @spec blocks(Macro.t(), [:test | :describe], env()) :: [test_block()]
  def blocks(ast, kinds, env \\ new_env()) do
    ast
    |> walk_env([], &collect_block(&1, &2, &3, kinds), env)
    |> Enum.reverse()
  end

  defp collect_block({kind, meta, [name | _tail] = args}, env, acc, kinds)
       when kind in [:test, :describe] do
    with true <- kind in kinds,
         [{:do, body} | _tail] <-
           args
           |> List.last()
           |> do_options() do
      block = %{
        kind: kind,
        name: name,
        line: meta[:line] || 1,
        args: args,
        body: body,
        env: env
      }

      {:cont, [block | acc]}
    else
      _other -> {:cont, acc}
    end
  end

  defp collect_block(_node, _env, acc, _kinds), do: {:cont, acc}

  defp do_options(options) when is_list(options) do
    if Keyword.keyword?(options) and Keyword.has_key?(options, :do), do: options, else: []
  end

  defp do_options(_other), do: []

  @doc "Literal text of a test name; interpolations contribute nothing."
  @spec name_text(Macro.t()) :: String.t()
  def name_text(name) when is_binary(name), do: name

  def name_text({:<<>>, _meta, parts}) do
    parts
    |> Enum.filter(&is_binary/1)
    |> Enum.join()
  end

  def name_text(_name), do: ""

  @doc "Text of the name only if it starts with a literal string (no leading interpolation)."
  @spec leading_text(Macro.t()) :: String.t() | nil
  def leading_text(name) when is_binary(name), do: name
  def leading_text({:<<>>, _meta, [first | _tail]}) when is_binary(first), do: first
  def leading_text(_name), do: nil

  @doc "Statements of a block body."
  @spec statements(Macro.t()) :: [Macro.t()]
  def statements({:__block__, _meta, statements}), do: statements
  def statements(nil), do: []
  def statements(statement), do: [statement]

  @doc ~S|Module name of an atom or a string such as `"Req"` or `":httpc"`.|
  @spec normalize_module(module() | String.t()) :: module_name()
  def normalize_module(module) when is_atom(module), do: atom_name(module)
  def normalize_module(":" <> _erlang = module), do: module
  def normalize_module("Elixir." <> module), do: module
  def normalize_module(module) when is_binary(module), do: module

  @doc "True when the file carries `@moduletag tag` (atom, list or keyword form)."
  @spec moduletag?(Macro.t(), atom() | nil) :: boolean()
  def moduletag?(_ast, disabled) when disabled in [nil, false], do: false

  def moduletag?(ast, tag) do
    walk(ast, false, fn
      {:@, _meta, [{:moduletag, _tag_meta, [value]}]}, acc -> acc or tag_value?(value, tag)
      _node, acc -> acc
    end)
  end

  defp tag_value?(value, tag) when is_list(value), do: Enum.any?(value, &tag_value?(&1, tag))
  defp tag_value?({key, _value}, tag), do: key == tag
  defp tag_value?(value, tag), do: value == tag

  defp collect_lines({_name, meta, _args} = node, acc) when is_list(meta) do
    extra = [
      meta[:line],
      meta[:end][:line],
      meta[:closing][:line],
      meta[:end_of_expression][:line]
    ]

    {node, Enum.reject(extra, &is_nil/1) ++ acc}
  end

  defp collect_lines(node, acc), do: {node, acc}

  @doc "Line of the first and last token of a node, including `end`/closing lines."
  @spec line_span(Macro.t()) :: {pos_integer(), pos_integer()}
  def line_span(ast) do
    {_ast, lines} = Macro.prewalk(ast, [], &collect_lines/2)

    case lines do
      [] -> {1, 1}
      lines -> Enum.min_max(lines)
    end
  end

  @doc "Compiles a pattern given as regex source string or `Regex`."
  @spec compile_pattern(Regex.t() | String.t()) :: Regex.t()
  def compile_pattern(%Regex{} = regex), do: regex
  def compile_pattern(source) when is_binary(source), do: Regex.compile!(source, "u")

  @doc "Matches `text` against any of `patterns`."
  @spec pattern_match?([Regex.t() | String.t()] | Regex.t() | String.t(), String.t()) ::
          boolean()
  def pattern_match?(patterns, text) do
    patterns
    |> List.wrap()
    |> Enum.any?(fn pattern ->
      pattern
      |> compile_pattern()
      |> Regex.match?(text)
    end)
  end

  @type comment :: %{
          line: pos_integer(),
          column: pos_integer(),
          text: String.t(),
          own_line?: boolean()
        }

  @doc """
  Real comments (never string or heredoc contents), as reported by the Elixir tokenizer.

  `text` has the `#` markers and surrounding whitespace removed.
  """
  @spec comments(SourceFile.t()) :: [comment()]
  def comments(%SourceFile{} = source_file) do
    source = SourceFile.source(source_file)

    case Code.string_to_quoted_with_comments(source, columns: true, emit_warnings: false) do
      {:ok, _ast, comments} ->
        lines = String.split(source, "\n")
        Enum.map(comments, &build_comment(&1, lines))

      _error ->
        []
    end
  end

  defp build_comment(%{line: line, column: column, text: text}, lines) do
    prefix =
      lines
      |> Enum.at(line - 1, "")
      |> String.slice(0, max(column - 1, 0))

    %{
      line: line,
      column: column,
      text:
        text
        |> String.trim_leading("#")
        |> String.trim(),
      own_line?: String.trim(prefix) == ""
    }
  end
end
