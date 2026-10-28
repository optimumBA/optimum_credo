defmodule Mix.Tasks.Optimum.HeexCheck do
  @shortdoc "Runs OptimumCredo's HEEx checks over standalone .heex files"

  @moduledoc """
  Runs `HardcodedAssetPath`, `HiddenIdInput` and `EventNameSnakeCase` over raw `.heex` files.

  Stock `mix credo` drops `.heex` files (it parses them as Elixir), so this task is the entry
  point for standalone templates. See `OptimumCredo.HeexCheck` for how files are matched and
  read.

      mix optimum.heex_check [PATH_OR_GLOB ...] [options]

  Without paths, `lib/**/*.heex` is used. Directories are searched recursively.

  ## Options

    * `--format text|json` - output format (default `text`)
    * `--checks A,B` - comma-separated check names (repeatable); default all
    * `--exclude PATH_OR_GLOB` - repeatable
    * `--prefix /images/` - repeatable, `HardcodedAssetPath` asset prefixes
    * `--allowed-field locale_id` - repeatable, `HiddenIdInput` accepted fields
    * `--allowed-event my-hook` - repeatable, `EventNameSnakeCase` accepted names
    * `--advisory` - findings do not change the exit status (real errors still do)

  ## Exit status

  `0` clean (or only findings with `--advisory`), `1` findings, `2` usage, read, path or check
  errors. JSON output is `{"files": [...], "findings": [...], "errors": [...], "notes": [...]}`.
  """

  use Mix.Task

  @switches [
    format: :string,
    checks: [:string, :keep],
    exclude: [:string, :keep],
    prefix: [:string, :keep],
    allowed_field: [:string, :keep],
    allowed_event: [:string, :keep],
    advisory: :boolean
  ]

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("loadpaths", ["--no-deps-check"])
    {status, output} = execute(args)
    if output != "", do: Mix.shell().info(output)
    if status != 0, do: System.halt(status)
    :ok
  end

  @doc """
  Runs the task without printing or halting; returns `{exit_status, output}`.
  """
  @spec execute([String.t()]) :: {0 | 1 | 2, String.t()}
  def execute(args) do
    case OptionParser.parse(args, strict: @switches) do
      {opts, paths, []} -> run_checks(opts, paths)
      {_opts, _paths, invalid} -> {2, usage_error(invalid)}
    end
  end

  defp usage_error(invalid) do
    options = Enum.map_join(invalid, ", ", fn {name, _value} -> name end)
    "optimum.heex_check: invalid option(s): #{options}\n\n" <> usage()
  end

  defp usage do
    "Usage: mix optimum.heex_check [PATH_OR_GLOB ...] [--format text|json] [--checks A,B] [--exclude P] [--prefix P] [--allowed-field F] [--allowed-event E] [--advisory]"
  end

  defp run_checks(opts, paths) do
    format = Keyword.get(opts, :format, "text")

    if format in ["text", "json"] do
      result = OptimumCredo.HeexCheck.run(paths, library_options(opts))
      {status(result, Keyword.get(opts, :advisory, false)), render(result, format)}
    else
      {2, "optimum.heex_check: unsupported format #{inspect(format)} (use text or json)"}
    end
  end

  defp library_options(opts) do
    lib_opts = [
      checks:
        opts
        |> Keyword.get_values(:checks)
        |> Enum.flat_map(&split/1),
      exclude: Keyword.get_values(opts, :exclude),
      prefixes: Keyword.get_values(opts, :prefix),
      allowed_fields: Keyword.get_values(opts, :allowed_field),
      allowed_events: Keyword.get_values(opts, :allowed_event)
    ]

    if Keyword.has_key?(opts, :checks), do: lib_opts, else: Keyword.delete(lib_opts, :checks)
  end

  defp split(value) do
    value
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
  end

  defp status(%{errors: [_head | _tail]}, _advisory), do: 2
  defp status(%{findings: [_head | _tail]}, false), do: 1
  defp status(_result, _advisory), do: 0

  defp render(result, "json") do
    result
    |> json_ready()
    |> Jason.encode!()
  end

  defp render(result, "text") do
    findings = for f <- result.findings, do: "#{f.file}:#{f.line}: [#{f.check}] #{f.message}"
    errors = for e <- result.errors, do: "error: #{e.message}"
    notes = for n <- result.notes, do: "note: #{n}"

    summary =
      "#{length(result.files)} file(s) checked, #{length(result.findings)} finding(s), #{length(result.errors)} error(s)"

    [findings, errors, notes, [summary]]
    |> Enum.concat()
    |> Enum.join("\n")
  end

  defp json_ready(%{errors: errors} = result),
    do: %{
      result
      | errors: Enum.map(errors, &Map.update!(&1, :kind, fn k -> Atom.to_string(k) end))
    }
end
