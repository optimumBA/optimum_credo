defmodule OptimumCredo.Check.Warning.AshCallWithoutActor do
  @moduledoc """
  Finds `Ash.get/read/create/update/destroy`-style calls on a resource module that pass
  neither `actor:` nor `authorize?: false`.

  Ash policies decide based on the actor. A call that omits it either fails authorization
  or, worse, is later "fixed" with `authorize?: false`. Pass `actor:` (and `tenant:` where the
  resource is multitenant) explicitly.

  **Gated by `ash: true`.** The check does nothing unless you set `ash: true`, so it can sit
  in a shared configuration and be switched on in Ash projects only.

  What is reported (files under `lib/` only):

  - `Ash.<function>(Resource, ...)` and `Resource |> Ash.<function>(...)` where the first
    argument is a module alias and no literal keyword list among the arguments contains
    `actor:` or `authorize?: false` (`authorize?: true` without an actor is reported);
  - `Resource.<function>(...)` for modules listed in `resource_modules` (code interfaces
    cannot be recognised statically), under the same condition.

  Not reported: calls whose first argument is a query, changeset or variable (they may carry
  the actor, for example from `Ash.Query.for_read(..., actor: user)`), calls where the options
  are an `opts`/`options` variable or built with `Keyword.*`/`Ash.Context.*`/`++`, resources
  in `actorless_resources`, and modules that `use Ash.Resource.*` or `Ash.Policy.*` helpers
  (changes, preparations, checks), which run with an implicit context.

  ## Parameters

  - `ash`: default `false`; set `true` to enable.
  - `actorless_resources`: resource modules (strings, such as `"MyApp.Catalog.Country"`, or
    atoms) that legitimately need no actor. Aliases in the checked file are resolved first.
  - `resource_modules`: modules whose every function call is treated as an Ash code interface.
  - `ash_functions`: `Ash` functions to inspect.
  """

  use Credo.Check,
    base_priority: :low,
    category: :warning,
    param_defaults: [
      ash: false,
      actorless_resources: [],
      resource_modules: [],
      ash_functions: [
        :get,
        :get!,
        :read,
        :read!,
        :read_one,
        :read_one!,
        :create,
        :create!,
        :update,
        :update!,
        :destroy,
        :destroy!,
        :load,
        :load!,
        :count,
        :count!,
        :exists?,
        :bulk_create,
        :bulk_create!,
        :bulk_update,
        :bulk_update!,
        :bulk_destroy,
        :bulk_destroy!
      ]
    ],
    explanations: [
      check: """
      Pass the actor to Ash calls so policies can authorize them.

      ## Bad

      ```elixir
      Ash.read!(MyApp.Blog.Post)
      ```

      ## Good

      ```elixir
      Ash.read!(MyApp.Blog.Post, actor: current_user, tenant: tenant)
      ```

      Set `ash: true` to enable the check. Queries and changesets that already carry the actor
      are not analysed.
      """,
      params: [
        ash: "Enable the Ash heuristics (default false).",
        actorless_resources: "Resource modules that do not need an actor.",
        resource_modules: "Modules whose functions are Ash code interfaces.",
        ash_functions: "Ash functions to inspect."
      ]
    ]

  alias OptimumCredo.OptimumDataSupport

  @implicit_context_prefixes [[:Ash, :Resource], [:Ash, :Policy]]

  @doc false
  @spec run(Credo.SourceFile.t(), keyword()) :: [Credo.Issue.t()]
  def run(%Credo.SourceFile{} = source_file, params) do
    ast = Credo.SourceFile.ast(source_file)

    if Params.get(params, :ash, __MODULE__) == true and
         OptimumDataSupport.in_dir?(source_file, "lib/") and
         not implicit_context?(ast) do
      ash_issues(ast, IssueMeta.for(source_file, params), params)
    else
      []
    end
  end

  defp ash_issues(ast, issue_meta, params) do
    functions = Params.get(params, :ash_functions, __MODULE__)
    actorless = configured_modules(params, :actorless_resources)
    resources = configured_modules(params, :resource_modules)

    ast
    |> OptimumDataSupport.expand_aliases()
    |> calls_with_subjects()
    |> Enum.filter(&without_actor?(&1, functions, resources, actorless))
    |> Enum.map(fn {_module, function, _args, meta, _subject} ->
      format_issue(issue_meta,
        message:
          "Ash call `#{function}` has no `actor:`; pass the actor (and tenant) so policies apply.",
        trigger: to_string(function),
        line_no: OptimumDataSupport.line(meta)
      )
    end)
  end

  defp configured_modules(params, key) do
    params
    |> Params.get(key, __MODULE__)
    |> Enum.map(&module_name/1)
  end

  defp implicit_context?(ast) do
    OptimumDataSupport.contains?(ast, fn
      {:use, _meta, [{:__aliases__, _alias_meta, segments} | _tail]} when is_list(segments) ->
        Enum.any?(
          @implicit_context_prefixes,
          &(List.starts_with?(segments, &1) and length(segments) > length(&1))
        )

      _node ->
        false
    end)
  end

  # Remote calls with the "subject": the piped-in value, or else the first argument.
  defp calls_with_subjects(ast) do
    pipes = piped_subjects(ast)

    ast
    |> OptimumDataSupport.remote_calls()
    |> Enum.map(fn {module, function, args, meta} ->
      subject = Map.get_lazy(pipes, {meta[:line], meta[:column]}, fn -> List.first(args) end)
      {module, function, args, meta, subject}
    end)
  end

  defp piped_subjects(ast) do
    {_ast, pipes} =
      Macro.prewalk(ast, %{}, fn
        {:|>, _meta, [subject, {{:., _dot_meta, _dot_args}, meta, _args}]} = node, acc ->
          {node, Map.put(acc, {meta[:line], meta[:column]}, subject)}

        node, acc ->
          {node, acc}
      end)

    pipes
  end

  defp without_actor?({module, function, args, _meta, subject}, functions, resources, actorless) do
    resource = resource_name(subject)

    ash_call? = module == [:Ash] and function in functions and not is_nil(resource)
    interface_call? = is_list(module) and Enum.join(module, ".") in resources

    (ash_call? or interface_call?) and resource not in actorless and no_actor_option?(args)
  end

  defp resource_name({:__aliases__, _meta, segments}) when is_list(segments) do
    if Enum.all?(segments, &is_atom/1), do: Enum.join(segments, ".")
  end

  defp resource_name(_other), do: nil

  # `"MyApp.Post"` and `MyApp.Post` (an atom, `Elixir.` prefix) name the same module.
  defp module_name(module) do
    module
    |> to_string()
    |> String.replace_prefix("Elixir.", "")
  end

  defp no_actor_option?(args) do
    OptimumDataSupport.fetch_option(args, :actor) == :error and
      not authorization_decided?(args) and
      not Enum.any?(args, &opaque_options?/1)
  end

  # `authorize?: false` (or a value only known at runtime) is a decision; `authorize?: true`
  # still has no actor to authorize.
  defp authorization_decided?(args) do
    case OptimumDataSupport.fetch_option(args, :authorize?) do
      :error -> false
      {:ok, true} -> false
      {:ok, _value} -> true
    end
  end

  defp opaque_options?({name, _meta, context}) when is_atom(name) and is_atom(context) do
    name
    |> Atom.to_string()
    |> String.contains?(["opts", "options"])
  end

  defp opaque_options?({:++, _meta, _args}), do: true

  defp opaque_options?(
         {{:., _meta, [{:__aliases__, _alias_meta, segments}, _second]}, _tuple_meta, _args}
       )
       when is_list(segments),
       do: List.first(segments) == :Keyword or segments == [:Ash, :Context]

  defp opaque_options?(_other), do: false
end
