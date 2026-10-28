defmodule OptimumCredo.Check.Refactor.DuplicateHandleEvent do
  @moduledoc """
  Finds `handle_event/3` clauses whose parameters and body are identical in several LiveView
  or LiveComponent modules.

  Shared handlers can move to an `on_mount` hook, `attach_hook/4` or a shared function. The
  comparison runs across all analysed files, ignores line numbers and the event name, and
  treats variables as equal when they are used in the same positions (alpha-renaming).
  Clauses smaller than `min_nodes` AST call nodes are skipped, and identical clauses within a
  single module are not reported.

  Identical text does not always mean identical behaviour, so a clause is skipped when it
  calls a function defined in its own module (a private helper of the same name and arity is
  a different function in each module) or uses `__MODULE__`/`__ENV__`. Module attributes are
  compared by name and value, and `alias`es declared in the module (`alias A.B`, `as:`, and
  `A.{B, C}`) are expanded; aliases injected by `use MyWeb, :live_view` are not visible, nor are
  imports, so two spellings of the same call from different imports compare by text.

  Only modules recognised as LiveViews (`use Phoenix.LiveView`, `use MyWeb, :live_view`, and
  the component equivalents) are compared. Bodies that differ in any literal or call are
  considered different. It is a hint: duplicated code is sometimes the clearer choice.

  ## Parameters

  - `min_nodes`: smallest clause size, in AST call nodes (default `4`).
  - `min_modules`: number of distinct modules that must share a clause (default `2`).
  """

  use Credo.Check,
    base_priority: :low,
    category: :refactor,
    param_defaults: [min_nodes: 4, min_modules: 2],
    explanations: [
      check: """
      Identical `handle_event/3` clauses in several LiveViews usually belong in an `on_mount`
      hook (`attach_hook/4`) or a shared function. Compared across all files, after
      alpha-renaming variables; trivial clauses are skipped. Opt-in, low priority.
      """,
      params: [
        min_nodes: "Smallest clause size, in AST call nodes, that is compared.",
        min_modules: "How many distinct modules must contain the same clause."
      ]
    ]

  alias Credo.Execution.ExecutionIssues
  alias OptimumCredo.OptimumIdiomsSupport

  @doc false
  @spec run_on_all_source_files(Credo.Execution.t(), [Credo.SourceFile.t()], keyword()) :: :ok
  def run_on_all_source_files(exec, source_files, params) do
    min_nodes = Params.get(params, :min_nodes, __MODULE__)
    min_modules = Params.get(params, :min_modules, __MODULE__)

    source_files
    |> Enum.reject(&OptimumIdiomsSupport.heex_file?/1)
    |> Enum.flat_map(&clauses(&1, params, min_nodes))
    |> Enum.group_by(& &1.key)
    |> Enum.filter(fn {_key, group} -> distinct_modules(group) >= min_modules end)
    |> Enum.flat_map(fn {_key, group} -> group end)
    |> Enum.each(&report(exec, &1))

    :ok
  end

  defp distinct_modules(group) do
    group
    |> Enum.uniq_by(& &1.module)
    |> length()
  end

  defp report(exec, clause) do
    issue =
      format_issue(clause.issue_meta,
        message:
          "`handle_event(#{inspect(clause.event)}, ...)` is identical in other LiveViews; consider `on_mount`/`attach_hook` or a shared function.",
        line_no: clause.line
      )

    ExecutionIssues.append(exec, clause.source_file, issue)
  end

  defp clauses(source_file, params, min_nodes) do
    issue_meta = IssueMeta.for(source_file, params)

    Credo.Code.prewalk(source_file, &collect_clauses(&1, &2, source_file, issue_meta, min_nodes))
  end

  defp collect_clauses(
         {:defmodule, _meta, [name, [do: body]]} = node,
         acc,
         source_file,
         issue_meta,
         min_nodes
       ) do
    statements = OptimumIdiomsSupport.statements(body)

    found =
      if OptimumIdiomsSupport.live_kind(statements) do
        module = {source_file.filename, Macro.to_string(name)}
        context = module_context(statements)

        for statement <- statements,
            clause = handle_event(statement, module, context, source_file, issue_meta, min_nodes),
            do: clause
      else
        []
      end

    {node, acc ++ found}
  end

  defp collect_clauses(node, acc, _source_file, _issue_meta, _min_nodes), do: {node, acc}

  defp split_guard({:when, _meta, [head, guard]}), do: {head, guard}
  defp split_guard(head), do: {head, nil}

  defp handle_event(
         {:def, meta, [head, [do: body]]},
         module,
         context,
         source_file,
         issue_meta,
         min_nodes
       ) do
    {head, guard} = split_guard(head)

    with {:handle_event, _meta, [event, params, socket]} when is_binary(event) <- head,
         clause = OptimumIdiomsSupport.unpipe([params, socket, guard, body]),
         true <- portable?(clause, context),
         key = normalize(clause, context),
         true <- node_count(key) >= min_nodes do
      %{
        key: key,
        module: module,
        event: event,
        line: meta[:line] || 1,
        source_file: source_file,
        issue_meta: issue_meta
      }
    else
      _other -> nil
    end
  end

  defp handle_event(_statement, _module, _context, _source_file, _issue_meta, _min_nodes),
    do: nil

  # What the clause can refer to that is not visible in its own text: local functions, the
  # module's attributes and aliases.
  defp module_context(statements) do
    %{
      locals:
        for(
          {kind, _meta, [head | _tail]} <- statements,
          kind in [:def, :defp, :defmacro, :defmacrop],
          into: MapSet.new(),
          do: local_name(head)
        ),
      attributes:
        for(
          {:@, _meta, [{name, _tuple_meta, [value]}]} <- statements,
          into: %{},
          do: {name, OptimumIdiomsSupport.strip_meta(value)}
        ),
      aliases: Enum.reduce(statements, %{}, &collect_aliases/2)
    }
  end

  defp local_name({:when, _meta, [head | _tail]}), do: local_name(head)

  defp local_name({name, _meta, args}) when is_atom(name) and is_list(args),
    do: {name, length(args)}

  defp local_name({name, _meta, _args}) when is_atom(name), do: {name, 0}
  defp local_name(_head), do: nil

  defp collect_aliases({:alias, _meta, [{:__aliases__, _alias_meta, parts}]}, acc),
    do: Map.put(acc, List.last(parts), parts)

  defp collect_aliases({:alias, _meta, [{:__aliases__, _alias_meta, parts}, opts]}, acc)
       when is_list(opts) do
    case opts[:as] do
      {:__aliases__, _meta, [short]} -> Map.put(acc, short, parts)
      _other -> acc
    end
  end

  defp collect_aliases(
         {:alias, _meta,
          [{{:., _dot_meta, [{:__aliases__, _alias_meta, base}, :{}]}, _tuple_meta, children}]},
         acc
       ) do
    Enum.reduce(children, acc, fn {:__aliases__, _meta, parts}, acc ->
      Map.put(acc, List.last(parts), base ++ parts)
    end)
  end

  defp collect_aliases(_statement, acc), do: acc

  # A clause that calls a function defined in its own module, or uses `__MODULE__`, means
  # something different in each module even when the text is identical.
  defp portable?(clause, context) do
    {_ast, portable?} = Macro.prewalk(clause, true, &portable_node(&1, &2, context))

    portable?
  end

  defp portable_node({:__MODULE__, _meta, ctx} = node, _ok, _context) when is_atom(ctx),
    do: {node, false}

  defp portable_node({:__ENV__, _meta, ctx} = node, _ok, _context) when is_atom(ctx),
    do: {node, false}

  defp portable_node({name, _meta, args} = node, ok, context)
       when is_atom(name) and is_list(args) do
    {node, ok and not MapSet.member?(context.locals, {name, length(args)})}
  end

  defp portable_node(node, ok, _context), do: {node, ok}

  # Drops metadata, resolves module-local aliases and attribute values, and renames variables
  # by first appearance so equal shapes compare equal. `_` is never renamed: two underscores
  # are two different anonymous patterns.
  defp normalize(ast, context) do
    {normalized, _names} =
      ast
      |> OptimumIdiomsSupport.strip_meta()
      |> Macro.prewalk(%{}, &normalize_node(&1, &2, context))

    normalized
  end

  defp normalize_node({:@, _meta, [{name, _tuple_meta, _args}]}, names, context) do
    rendered =
      context.attributes
      |> Map.get(name)
      |> Macro.to_string()

    {{:__attribute__, {name, rendered}}, names}
  end

  defp normalize_node({:__aliases__, _meta, [head | rest]}, names, context) do
    {{:__aliases__, [], Map.get(context.aliases, head, [head]) ++ rest}, names}
  end

  defp normalize_node({:_, _meta, ctx} = node, names, _context) when is_atom(ctx),
    do: {node, names}

  defp normalize_node({name, _meta, ctx}, names, _context) when is_atom(name) and is_atom(ctx) do
    if internal_name?(name) do
      {{name, [], ctx}, names}
    else
      names = Map.put_new(names, name, map_size(names))
      {{:__variable__, Map.fetch!(names, name)}, names}
    end
  end

  defp normalize_node(node, names, _context), do: {node, names}

  defp internal_name?(name) do
    name
    |> Atom.to_string()
    |> String.starts_with?("__")
  end

  defp node_count(ast) do
    ast
    |> Macro.prewalk(0, fn
      {_form, _meta, args} = node, count when is_list(args) -> {node, count + 1}
      node, count -> {node, count}
    end)
    |> elem(1)
  end
end
