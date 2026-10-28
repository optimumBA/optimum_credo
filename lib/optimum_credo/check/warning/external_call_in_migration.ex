defmodule OptimumCredo.Check.Warning.ExternalCallInMigration do
  @moduledoc """
  Finds calls to HTTP clients and other external-service modules inside migrations.

  Migrations should change the database only. A call to a third-party API makes the
  deploy depend on that service being up, cannot be rolled back, and is repeated for every
  fresh database. One-off work that talks to external services belongs in a script under
  `priv/`.

  The check reads remote calls (`Req.get!(...)`, `:httpc.request(...)`) whose module matches
  one of the configured prefixes in files under `priv/<repo>/migrations/`.

  ## Parameters

  - `external_modules`: modules (or prefixes of module names) considered external. Default:
    `HTTPoison`, `Req`, `Tesla`, `Finch`, `Mint`, `ExAws`, `Stripe`, `Swoosh`, `:httpc`,
    `:hackney`.
  - `ignore_files`: path suffixes or regexes of migrations to skip.

  Aliases are followed (`alias Req, as: Http` then `Http.get!/1`). Wrapper modules of your own
  are not recognised; add the wrapper to `external_modules`.
  """

  use Credo.Check,
    base_priority: :low,
    category: :warning,
    param_defaults: [
      external_modules: [
        "HTTPoison",
        "Req",
        "Tesla",
        "Finch",
        "Mint",
        "ExAws",
        "Stripe",
        "Swoosh",
        ":httpc",
        ":hackney"
      ],
      ignore_files: []
    ],
    explanations: [
      check: """
      Do not call external services from migrations.

      ## Bad

      ```elixir
      def up do
        Req.post!("https://api.example.com/sync", json: %{})
      end
      ```

      ## Good

      Put the one-off call in a script under `priv/` and keep the migration to schema and
      in-database changes.
      """,
      params: [
        external_modules: "Module names or name prefixes treated as external services.",
        ignore_files: "Path suffixes or regexes for migrations to skip."
      ]
    ]

  alias OptimumCredo.OptimumDataSupport

  @doc false
  @spec run(Credo.SourceFile.t(), keyword()) :: [Credo.Issue.t()]
  def run(%Credo.SourceFile{} = source_file, params) do
    ignore_files = Params.get(params, :ignore_files, __MODULE__)

    if OptimumDataSupport.migration?(source_file) and
         not OptimumDataSupport.ignored_file?(source_file, ignore_files) do
      external_issues(source_file, params)
    else
      []
    end
  end

  defp external_issues(source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)

    external =
      params
      |> Params.get(:external_modules, __MODULE__)
      |> Enum.map(&normalize/1)

    source_file
    |> Credo.SourceFile.ast()
    |> OptimumDataSupport.expand_aliases()
    |> OptimumDataSupport.remote_calls()
    |> Enum.filter(fn {module, _function, _args, _meta} -> external?(module, external) end)
    |> Enum.map(fn {module, function, _args, meta} ->
      name = display(module)

      format_issue(issue_meta,
        message:
          "Migration calls external service #{name}.#{function}; " <>
            "move one-off external calls to a script under priv/.",
        trigger: name,
        line_no: OptimumDataSupport.line(meta)
      )
    end)
  end

  # An Erlang module stays a ":name" string; an Elixir module becomes its segment names.
  defp normalize(":" <> _erlang = module), do: module
  defp normalize(module) when is_binary(module), do: String.split(module, ".")

  defp normalize(module) when is_atom(module) do
    module
    |> inspect()
    |> normalize()
  end

  defp external?(module, external) when is_atom(module),
    do: (":" <> Atom.to_string(module)) in external

  defp external?(segments, external) do
    names = Enum.map(segments, &segment_name/1)
    Enum.any?(external, &(is_list(&1) and List.starts_with?(names, &1)))
  end

  defp segment_name(segment) when is_atom(segment), do: Atom.to_string(segment)
  defp segment_name(segment), do: segment

  defp display(module) when is_atom(module), do: inspect(module)
  defp display(segments), do: Enum.join(segments, ".")
end
