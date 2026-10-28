defmodule OptimumCredo.Check.Readability.ModuleSelfPrefix do
  @moduledoc """
  Finds `__MODULE__.fun(...)` calls to a function that the same module defines locally.

  Calling a local function directly (`fun(...)`) is the idiom; the `__MODULE__.`
  prefix is redundant. `%__MODULE__{}` structs, `__MODULE__.Child` aliases, and
  calls to functions the module does not define are never reported.

  This is a static heuristic. Local functions are the `def`, `defp`, and `defdelegate`
  heads written directly in the module body, matched by name and arity (a piped value
  counts as an argument, default arguments cover the lower arities, and
  `&__MODULE__.fun/2` captures count with their written arity). Macros are not matched,
  because a local macro call needs the definition to come first; functions injected by
  `use` or macros are unknown. Only code inside function clauses is inspected: at module
  level (`defstruct` defaults, attributes) the prefix is required because local functions
  cannot be captured or called there. A local function that shares its name and arity with
  an auto-imported `Kernel` function or macro (`inspect/1`, `to_string/1`, `send/2`, ...) is
  never reported, because dropping the prefix would not compile, unless a literal
  `import Kernel, except: [...]` or `only: [...]` earlier in the module removes it. Nested `defmodule` bodies are scanned with their own
  `__MODULE__`, and `quote` blocks are skipped because `__MODULE__` there expands in the
  caller. Deliberate self-calls (for hot code reloading or mocking) can be listed in
  `allow_self_prefix_for`.

  ## Parameters

  - `allow_self_prefix_for`: function names (atoms or strings) that may keep the prefix.
  """

  use Credo.Check,
    base_priority: :low,
    category: :readability,
    param_defaults: [allow_self_prefix_for: []],
    explanations: [
      check: """
      Call local functions directly instead of through `__MODULE__`.

      ## Bad

      ```elixir
      def run(x), do: __MODULE__.helper(x)
      def helper(x), do: x
      ```

      ## Good

      ```elixir
      def run(x), do: helper(x)
      def helper(x), do: x
      ```

      Functions defined by `use` or macros are unknown. Use `allow_self_prefix_for`
      for deliberate self-calls.
      """,
      params: [allow_self_prefix_for: "Function names that may keep the `__MODULE__.` prefix."]
    ]

  alias OptimumCredo.OptimumStructureSupport

  @doc false
  @spec run(Credo.SourceFile.t(), keyword()) :: [Credo.Issue.t()]
  def run(%Credo.SourceFile{} = source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)

    allowed =
      params
      |> Params.get(:allow_self_prefix_for, __MODULE__)
      |> OptimumStructureSupport.to_strings()

    source_file
    |> Credo.Code.prewalk(fn
      {:defmodule, _meta, [_name, [do: _body]]} = ast, issues ->
        {:skip, scan_module(ast, [], allowed, issues)}

      ast, issues ->
        {ast, issues}
    end)
    |> Enum.reverse()
    |> Enum.map(fn {name, line} ->
      format_issue(issue_meta,
        message: "Call local function #{name} directly instead of through __MODULE__.",
        line_no: line
      )
    end)
  end

  # `imports` holds the `import Kernel` directives in effect, as `{line, options}` in source
  # order. Nested modules inherit the directive in effect where they are defined.
  defp scan_module({:defmodule, meta, [_name, [do: body]]}, imports, allowed, issues) do
    statements = OptimumStructureSupport.statements(body)
    imports = inherited_import(imports, meta[:line]) ++ kernel_imports(statements)
    found = found_calls(OptimumStructureSupport.functions(statements), imports, allowed)

    {_body, issues} =
      Macro.prewalk(
        body,
        Enum.reverse(found, issues),
        &scan_nested(&1, &2, imports, allowed)
      )

    issues
  end

  defp scan_nested({:defmodule, _meta, [_first, [do: _do]]} = nested, issues, imports, allowed) do
    {:skip, scan_module(nested, imports, allowed, issues)}
  end

  defp scan_nested(node, issues, _imports, _allowed), do: {node, issues}

  defp found_calls(clauses, imports, allowed) do
    locals =
      clauses
      |> Enum.filter(&(&1.kind in [:def, :defp, :defdelegate]))
      |> Enum.map(&{&1.name, &1.arities})

    clauses
    |> Enum.flat_map(fn clause ->
      visible = visible_locals(locals, import_at(imports, clause.line))
      self_calls(clause.code, visible, 0)
    end)
    |> Enum.reject(fn {name, _value} -> Atom.to_string(name) in allowed end)
  end

  defp inherited_import(imports, line) do
    case import_at(imports, line) do
      :all -> []
      options -> [{0, options}]
    end
  end

  defp kernel_imports(statements) do
    Enum.flat_map(statements, fn
      {:import, meta, [{:__aliases__, _meta, [:Kernel]} | rest]} ->
        [{meta[:line] || 0, import_options(rest)}]

      _other ->
        []
    end)
  end

  defp import_options([options]) when is_list(options) do
    cond do
      is_list(options[:except]) -> {:except, options[:except]}
      is_list(options[:only]) -> {:only, options[:only]}
      options[:only] in [:functions, :macros, :sigils] -> {:only, options[:only]}
      true -> :all
    end
  end

  defp import_options(_other), do: :all

  # Imports are lexical and the latest `import Kernel` replaces earlier ones.
  defp import_at(imports, line) do
    latest =
      imports
      |> Enum.filter(fn {import_line, _options} -> import_line < line end)
      |> List.last()

    case latest do
      nil -> :all
      {_line, options} -> options
    end
  end

  # A local function whose name and arity match an auto-imported Kernel function or macro
  # cannot be called without the prefix, unless `import Kernel` was narrowed to drop it.
  defp visible_locals(locals, import) do
    Enum.flat_map(locals, fn {name, arities} ->
      case Enum.reject(arities, &kernel_conflict?(name, &1, import)) do
        [] -> []
        arities -> [{name, arities}]
      end
    end)
  end

  defp kernel_conflict?(name, arity, import) do
    kind =
      cond do
        {name, arity} in Kernel.__info__(:functions) -> :functions
        {name, arity} in Kernel.__info__(:macros) -> :macros
        true -> nil
      end

    kind != nil and not import_removes?(import, {name, arity}, kind)
  end

  defp import_removes?(:all, _name_arity, _kind), do: false
  defp import_removes?({:except, list}, name_arity, _kind), do: name_arity in list

  defp import_removes?({:only, kind}, _name_arity, imported) when is_atom(kind),
    do: kind != imported

  defp import_removes?({:only, list}, name_arity, _kind), do: name_arity not in list

  # `piped` is the number of arguments supplied by a pipeline to the call being inspected.
  defp self_calls({:defmodule, _meta, _args}, _locals, _piped), do: []
  defp self_calls({:quote, _meta, _args}, _locals, _piped), do: []

  defp self_calls({:|>, _meta, [left, right]}, locals, _piped),
    do: self_calls(left, locals, 0) ++ self_calls(right, locals, 1)

  defp self_calls({:&, _meta, [{:/, _meta2, [call, arity]}]}, locals, piped)
       when is_integer(arity) do
    case self_call(call, arity, locals) do
      nil -> self_calls(call, locals, piped)
      found -> [found]
    end
  end

  defp self_calls({{:., _dot, _target}, _meta, args} = call, locals, piped)
       when is_list(args) do
    own =
      call
      |> self_call(length(args) + piped, locals)
      |> List.wrap()

    own ++ self_calls(args, locals, 0)
  end

  defp self_calls(term, locals, _piped) when is_tuple(term) do
    term
    |> Tuple.to_list()
    |> Enum.flat_map(&self_calls(&1, locals, 0))
  end

  defp self_calls(list, locals, _piped) when is_list(list),
    do: Enum.flat_map(list, &self_calls(&1, locals, 0))

  defp self_calls(_term, _locals, _piped), do: []

  defp self_call({{:., _dot, [{:__MODULE__, _ctx_meta, ctx}, name]}, meta, _args}, arity, locals)
       when is_atom(ctx) and is_atom(name) do
    if Enum.any?(locals, fn {local, arities} -> local == name and arity in arities end),
      do: {name, meta[:line] || 1}
  end

  defp self_call(_call, _arity, _locals), do: nil
end
