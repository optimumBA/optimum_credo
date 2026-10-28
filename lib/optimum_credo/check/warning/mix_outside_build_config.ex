defmodule OptimumCredo.Check.Warning.MixOutsideBuildConfig do
  @moduledoc """
  Finds calls to `Mix` (`Mix.env/0`, `Mix.Project.config/0`, `Mix.shell/0`, ...) in
  application code and in `config/runtime.exs`.

  `Mix` is not available in a release, so a runtime call to it crashes in production while
  working in development. Use `config_env()` in `config/runtime.exs`, or compile-time
  configuration (`Application.compile_env/3`) instead.

  Checked: files under `lib/` and `config/runtime.exs`. Not checked: `lib/mix/tasks`
  (configurable with `allowed_paths`), `mix.exs`, `config/config.exs`, `config/dev.exs`,
  `config/test.exs`, `config/prod.exs`, and files that define a `Mix.Tasks.*` module (a Mix
  task is a Mix-only module wherever it lives).

  Only remote calls whose module is `Mix` or starts with `Mix.` are reported, also through an
  alias (`alias Mix.Project` then `Project.config()`).
  `use Mix.Task` and `@behaviour Mix.Task` are not calls.

  ## Parameters

  - `allowed_paths`: directory fragments where Mix calls are fine, default `["lib/mix/tasks"]`.
  - `allow_ensure_loaded_guard`: default `true`. A call inside a branch guarded by
    `Code.ensure_loaded?(Mix)` or `function_exported?(Mix, ...)` is accepted, for libraries that
    support both worlds.

  The check cannot tell compile-time uses (`@env Mix.env()` evaluated while compiling) from
  runtime ones; both are reported.
  """

  use Credo.Check,
    base_priority: :low,
    category: :warning,
    param_defaults: [allowed_paths: ["lib/mix/tasks"], allow_ensure_loaded_guard: true],
    explanations: [
      check: """
      `Mix` does not exist in releases; do not call it from application code.

      ## Bad

      ```elixir
      # lib/my_app/mailer.ex
      if Mix.env() == :prod, do: deliver(email)
      ```

      ## Good

      ```elixir
      # config/runtime.exs
      config :my_app, deliver_emails?: config_env() == :prod
      ```

      Calls guarded by `Code.ensure_loaded?(Mix)` are accepted.
      """,
      params: [
        allowed_paths: "Directory fragments where Mix calls are allowed.",
        allow_ensure_loaded_guard: "Accept calls guarded by Code.ensure_loaded?(Mix)."
      ]
    ]

  alias OptimumCredo.OptimumDataSupport

  @doc false
  @spec run(Credo.SourceFile.t(), keyword()) :: [Credo.Issue.t()]
  def run(%Credo.SourceFile{} = source_file, params) do
    allowed_paths = Params.get(params, :allowed_paths, __MODULE__)

    with true <- checked_file?(source_file, allowed_paths),
         ast = Credo.SourceFile.ast(source_file),
         false <- mix_task?(ast) do
      issue_meta = IssueMeta.for(source_file, params)
      guard = guard(Params.get(params, :allow_ensure_loaded_guard, __MODULE__))

      ast
      |> OptimumDataSupport.expand_aliases()
      |> OptimumDataSupport.unguarded_nodes(guard, &mix_call?/1)
      |> Enum.map(&issue(&1, issue_meta))
    else
      _other -> []
    end
  end

  defp guard(guarded?), do: if(guarded?, do: &mix_guard?/1, else: &never_guarded?/1)

  defp never_guarded?(_condition), do: false

  defp checked_file?(source_file, allowed_paths) do
    (OptimumDataSupport.in_dir?(source_file, "lib/") and
       not OptimumDataSupport.in_any_dir?(source_file, normalize_dirs(allowed_paths))) or
      OptimumDataSupport.ends_with_path?(source_file, "config/runtime.exs")
  end

  defp normalize_dirs(paths) do
    paths
    |> List.wrap()
    |> Enum.map(&String.trim_leading(&1, "/"))
  end

  defp mix_task?(ast) do
    ast
    |> OptimumDataSupport.modules()
    |> Enum.any?(fn {name, _body} -> match?({:__aliases__, _, [:Mix, :Tasks | _]}, name) end)
  end

  defp mix_call?(node) do
    match?({[:Mix | _], _function, _args, _meta}, OptimumDataSupport.remote_call(node))
  end

  defp mix_guard?(condition) do
    OptimumDataSupport.contains?(condition, fn
      {{:., _meta, [{:__aliases__, _alias_meta, [:Code]}, :ensure_loaded?]}, _tuple_meta,
       [{:__aliases__, _ignored, [:Mix | _tail]}]} ->
        true

      {:function_exported?, _meta, [{:__aliases__, _alias_meta, [:Mix | _tail]} | _tail2]} ->
        true

      _node ->
        false
    end)
  end

  defp issue(node, issue_meta) do
    {module, function, _args, meta} = OptimumDataSupport.remote_call(node)
    name = "#{Enum.join(module, ".")}.#{function}"

    format_issue(issue_meta,
      message:
        "#{name} is unavailable in releases; use config_env() in runtime.exs or compile-time config.",
      trigger: name,
      line_no: OptimumDataSupport.line(meta)
    )
  end
end
