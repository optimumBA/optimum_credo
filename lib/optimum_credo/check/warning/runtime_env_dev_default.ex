defmodule OptimumCredo.Check.Warning.RuntimeEnvDevDefault do
  @moduledoc """
  A check that finds hardcoded developer-machine paths used as `System.get_env` defaults
  in `config/runtime.exs`.

  Using a developer-machine path as a runtime default causes the application to silently
  use a path that does not exist on production servers, leading to confusing failures at
  boot or at runtime.

  Detected patterns:

  - `System.get_env("VAR", "/Users/...")` — macOS home directory
  - `System.get_env("VAR", "/home/...")` — Linux home directory
  - `System.get_env("VAR", "~/...")` — tilde-expanded home path

  The check does NOT fire on:

  - `System.get_env("VAR")` — no default, safe
  - `System.get_env("VAR") || "/Users/..."` — fallback via `||`, not a literal default
  - `Path.expand("~/foo")` — a function call, not a string literal default
  - Files other than `config/runtime.exs`

  This check is file-scoped to `config/runtime.exs` only.
  """

  use Credo.Check,
    base_priority: :high,
    category: :warning,
    explanations: [
      check: """
      Hardcoded developer-machine paths in `System.get_env/2` defaults will cause the
      application to silently read from a non-existent path on production servers.

      ## Examples

      **Bad:**
      ```elixir
      # config/runtime.exs
      codegen_dir = System.get_env("CODEGEN_DIR", "/Users/me/codegen")
      ```

      **Good:**
      ```elixir
      # config/runtime.exs
      codegen_dir = System.get_env("CODEGEN_DIR")
      # Require the var to be set in prod; use a .env file locally.
      ```
      """
    ]

  @doc false
  @spec run(Credo.SourceFile.t(), keyword()) :: [Credo.Issue.t()]
  def run(%Credo.SourceFile{} = source_file, params) do
    filename = source_file.filename || ""

    if String.ends_with?(filename, "config/runtime.exs") do
      issue_meta = IssueMeta.for(source_file, params)
      Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta))
    else
      []
    end
  end

  defp traverse(ast, issues, issue_meta) do
    case find_dev_default(ast, issue_meta) do
      nil -> {ast, issues}
      issue -> {ast, [issue | issues]}
    end
  end

  # System.get_env("KEY", "default_string")
  defp find_dev_default(
         {{:., meta, [{:__aliases__, _alias_meta, [:System]}, :get_env]}, _call_meta,
          [_key_ast, default_ast]},
         issue_meta
       )
       when is_binary(default_ast) do
    if dev_machine_path?(default_ast) do
      format_issue(issue_meta,
        message:
          "Hardcoded developer-machine path \"#{default_ast}\" as System.get_env default in " <>
            "runtime.exs — use a non-path default or no default and let the call fail in prod.",
        line_no: meta[:line] || 1
      )
    end
  end

  defp find_dev_default(_ast, _issue_meta), do: nil

  defp dev_machine_path?(string) do
    String.starts_with?(string, ["/Users/", "/home/", "~/"])
  end
end
