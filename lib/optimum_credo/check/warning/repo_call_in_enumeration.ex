defmodule OptimumCredo.Check.Warning.RepoCallInEnumeration do
  @moduledoc """
  Finds `Repo` queries issued once per element of an enumeration (a likely N+1).

  Reported:

  - a `Repo.get/get!/get_by/get_by!/one/one!/all/exists?/aggregate/reload/reload!/preload`
    call inside the function (or capture) given to `Enum.map/each/flat_map/filter/reduce/...`
    or `Stream.*`;
  - the same inside the body, a filter, or the right-hand side of a later generator of a
    `for` comprehension (the first generator's collection runs once and is not reported).

  Per-row queries cost one database round trip each. Prefer a single query with `where ... in`,
  a join, `preload`, `exists?`/`count` instead of loading, or `update_all`.

  This is a lexical heuristic with known blind spots: queries reached through a helper
  function (`Enum.map(ids, &fetch/1)`) are invisible, and small fixed collections
  (three configured items) are reported even though they are harmless. Aliases are followed
  (`alias MyApp.Repo, as: R`), but only a module whose last segment is `Repo` counts.

  ## Parameters

  - `repo_functions`: `Repo` functions treated as queries.
  - `enumerator_functions`: `Enum`/`Stream` functions whose function arguments run per element.
  - `ignore_paths`: directories skipped entirely, default `["test/", "priv/"]`.
  """

  use Credo.Check,
    base_priority: :low,
    category: :warning,
    param_defaults: [
      repo_functions: [
        :get,
        :get!,
        :get_by,
        :get_by!,
        :one,
        :one!,
        :all,
        :exists?,
        :aggregate,
        :reload,
        :reload!,
        :preload
      ],
      enumerator_functions: [
        :map,
        :flat_map,
        :each,
        :filter,
        :reject,
        :reduce,
        :reduce_while,
        :map_reduce,
        :find,
        :find_value,
        :any?,
        :all?,
        :count,
        :sort_by,
        :group_by,
        :min_by,
        :max_by,
        :map_every
      ],
      ignore_paths: ["test/", "priv/"]
    ],
    explanations: [
      check: """
      Do not query the database once per element.

      ## Bad

      ```elixir
      Enum.map(posts, fn post -> Repo.get(User, post.user_id) end)
      ```

      ## Good

      ```elixir
      users = Repo.all(from u in User, where: u.id in ^Enum.map(posts, & &1.user_id))
      ```

      A lexical heuristic: helper functions called from the loop are not followed.
      """,
      params: [
        repo_functions: "Repo functions treated as queries.",
        enumerator_functions: "Enum/Stream functions whose function arguments run per element.",
        ignore_paths: "Directories (like `test/`) that are not checked."
      ]
    ]

  alias OptimumCredo.OptimumDataSupport

  @doc false
  @spec run(Credo.SourceFile.t(), keyword()) :: [Credo.Issue.t()]
  def run(%Credo.SourceFile{} = source_file, params) do
    if OptimumDataSupport.in_any_dir?(source_file, Params.get(params, :ignore_paths, __MODULE__)) do
      []
    else
      issue_meta = IssueMeta.for(source_file, params)
      repo_functions = Params.get(params, :repo_functions, __MODULE__)
      enumerators = Params.get(params, :enumerator_functions, __MODULE__)

      source_file
      |> Credo.SourceFile.ast()
      |> OptimumDataSupport.expand_aliases()
      |> per_element_bodies(enumerators)
      |> Enum.flat_map(&repo_calls(&1, repo_functions))
      |> Enum.uniq_by(fn {_function, meta} -> {OptimumDataSupport.line(meta), meta[:column]} end)
      |> Enum.map(fn {function, meta} ->
        format_issue(issue_meta,
          message:
            "Repo.#{function} runs once per element of an enumeration (N+1 query); " <>
              "load the data in one query instead.",
          trigger: "Repo.#{function}",
          line_no: OptimumDataSupport.line(meta)
        )
      end)
    end
  end

  # Code that runs once per element: fn/capture arguments of enumerators, `for` bodies.
  defp per_element_bodies(ast, enumerators) do
    {_ast, bodies} = Macro.prewalk(ast, [], &collect_bodies(&1, &2, enumerators))

    bodies
  end

  defp collect_bodies(
         {{:., _dot_meta, [{:__aliases__, _alias_meta, [module]}, function]}, _meta, args} = node,
         acc,
         enumerators
       )
       when module in [:Enum, :Stream] and is_list(args) do
    if function in enumerators,
      do: {node, Enum.filter(args, &callable?/1) ++ acc},
      else: {node, acc}
  end

  defp collect_bodies({:for, _meta, args} = node, acc, _enumerators) when is_list(args),
    do: {node, for_bodies(args) ++ acc}

  defp collect_bodies(node, acc, _enumerators), do: {node, acc}

  defp callable?({:fn, _meta, _args}), do: true
  defp callable?({:&, _meta, _args}), do: true
  defp callable?(_other), do: false

  defp for_bodies(args) do
    {generators, rest} = Enum.split_with(args, &match?({:<-, _meta, _args}, &1))

    later_collections =
      for {:<-, _meta, [_pattern, collection]} <- Enum.drop(generators, 1), do: collection

    bodies =
      Enum.flat_map(rest, fn
        options when is_list(options) ->
          options
          |> Keyword.take([:do, :reduce])
          |> Keyword.values()

        filter ->
          [filter]
      end)

    later_collections ++ bodies
  end

  defp repo_calls(body, repo_functions) do
    {_ast, calls} =
      Macro.prewalk(body, [], fn
        {{:., _meta, [module, function]}, meta, args} = node, acc when is_list(args) ->
          if OptimumDataSupport.last_segment(module) == :Repo and function in repo_functions,
            do: {node, [{function, meta} | acc]},
            else: {node, acc}

        node, acc ->
          {node, acc}
      end)

    calls
  end
end
