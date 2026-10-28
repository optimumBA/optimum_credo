defmodule OptimumCredo.HeexCheck do
  @moduledoc """
  Runs the HEEx-capable OptimumCredo checks over standalone `.heex` files.

  Stock Credo parses every selected file as Elixir and drops `.heex` files as invalid, so the
  checks below never see them in a normal `mix credo` run. This module reads each file as text,
  builds a `Credo.SourceFile` with `Credo.SourceFile.parse/2` and hands it straight to the
  check's `run/2`. The parse attempt populates Credo's source cache; these checks inspect
  the original template text even when Credo marks it invalid. No template code is evaluated.

  Checks (selectable by `--checks`, in snake_case, CamelCase or fully qualified form):

    * `HardcodedAssetPath` (params: `prefixes`)
    * `HiddenIdInput` (params: `allowed_fields`)
    * `EventNameSnakeCase` (params: `allowed_events`)

  ## Options for `run/2`

    * `:checks` - list of check names. Default: all three.
    * `:exclude` - list of paths or globs removed from the matched files (a directory excludes
      everything below it).
    * `:prefixes`, `:allowed_fields`, `:allowed_events` - lists of strings passed to the
      matching check.

  ## Files

  `paths` entries may be files (must end in `.heex`), directories (searched recursively for
  `*.heex`) or globs (only `.heex` matches are kept). With no paths, `lib/**/*.heex` is used and
  matching nothing is reported as a note, not an error. An explicit path that does not exist, or a
  glob that matches nothing, is an error. Symlinks are followed (`Path.wildcard/1` and
  `File.read/1` do); files are deduplicated by absolute path and results are sorted.

  ## Result

  `run/2` returns a map with `:files` (checked paths), `:findings` (sorted, deduplicated maps with
  `:check`, `:file`, `:line`, `:message`), `:errors` (maps with `:kind`, `:message` and
  optionally `:file`/`:check`; kinds `:bad_path`, `:bad_option`, `:unknown_check`, `:read`,
  `:check_failed`) and `:notes`. A check that raises is reported as `:check_failed`, never as
  "no findings".
  """

  alias OptimumCredo.Check.Readability.EventNameSnakeCase
  alias OptimumCredo.Check.Warning.HardcodedAssetPath
  alias OptimumCredo.Check.Warning.HiddenIdInput

  @default_glob "lib/**/*.heex"

  @checks %{
    "HardcodedAssetPath" => {HardcodedAssetPath, :prefixes},
    "HiddenIdInput" => {HiddenIdInput, :allowed_fields},
    "EventNameSnakeCase" => {EventNameSnakeCase, :allowed_events}
  }

  @type error :: %{
          required(:kind) => atom(),
          required(:message) => String.t(),
          optional(:file) => String.t(),
          optional(:check) => String.t()
        }
  @type finding :: %{
          check: String.t(),
          file: String.t(),
          line: pos_integer() | nil,
          message: String.t()
        }
  @type result :: %{
          files: [String.t()],
          findings: [finding()],
          errors: [error()],
          notes: [String.t()]
        }

  @doc "Names of the available checks."
  @spec check_names() :: [String.t()]
  def check_names do
    @checks
    |> Map.keys()
    |> Enum.sort()
  end

  @doc "Runs the selected checks over the files matched by `paths`. See the moduledoc."
  @spec run([String.t()], keyword()) :: result()
  def run(paths, opts \\ []) when is_list(paths) and is_list(opts) do
    # `Credo.SourceFile.parse/2` caches its AST in a Credo service process.
    {:ok, _started} = Application.ensure_all_started(:credo)

    {checks, check_errors} =
      opts
      |> Keyword.get(:checks)
      |> select_checks()

    option_errors = validate_options(opts)

    if check_errors ++ option_errors != [] do
      result([], [], check_errors ++ option_errors, [])
    else
      {files, path_errors, notes} = resolve_files(paths, Keyword.get(opts, :exclude, []))
      {findings, run_errors} = analyse(files, checks, opts)
      result(files, findings, path_errors ++ run_errors, notes)
    end
  end

  defp result(files, findings, errors, notes) do
    %{
      files: files,
      findings:
        findings
        |> Enum.uniq()
        |> Enum.sort_by(&{&1.file, &1.line || 0, &1.check, &1.message}),
      errors: Enum.uniq(errors),
      notes: notes
    }
  end

  # -- checks and options ----------------------------------------------------

  defp select_checks(nil), do: select_checks(check_names())
  defp select_checks([]), do: {[], [error(:unknown_check, "no checks selected")]}

  defp select_checks(names) when is_list(names) do
    {found, errors} =
      Enum.reduce(names, {[], []}, fn name, {found, errors} ->
        case lookup(name) do
          {:ok, key} ->
            {[key | found], errors}

          :error ->
            known = Enum.join(check_names(), ", ")

            {found,
             [error(:unknown_check, "unknown check #{inspect(name)} (known: #{known})") | errors]}
        end
      end)

    {found
     |> Enum.uniq()
     |> Enum.sort(), Enum.reverse(errors)}
  end

  defp select_checks(other),
    do: {[], [error(:bad_option, ":checks must be a list, got #{inspect(other)}")]}

  # Matches by comparing normalised strings against the fixed table: no atoms are created.
  defp lookup(name) when is_binary(name) or is_atom(name) do
    wanted =
      name
      |> to_string()
      |> String.replace_prefix("Elixir.", "")
      |> normalise()

    @checks
    |> Map.keys()
    |> Enum.find_value(:error, fn key ->
      if wanted in [
           normalise(key),
           normalise("OptimumCredo.Check.Warning." <> key),
           normalise("OptimumCredo.Check.Readability." <> key)
         ],
         do: {:ok, key}
    end)
  end

  defp lookup(_name), do: :error

  defp normalise(name) do
    name
    |> String.replace(["_", "-"], "")
    |> String.downcase()
  end

  defp validate_options(opts) do
    known = [:checks, :exclude, :prefixes, :allowed_fields, :allowed_events]

    unknown =
      for {key, _value} <- opts,
          key not in known,
          do: error(:bad_option, "unknown option #{inspect(key)}")

    bad =
      for key <- [:exclude, :prefixes, :allowed_fields, :allowed_events],
          value = Keyword.get(opts, key, []),
          not (is_list(value) and Enum.all?(value, &is_binary/1)),
          do: error(:bad_option, "#{key} must be a list of strings")

    unknown ++ bad
  end

  # -- files -----------------------------------------------------------------

  defp resolve_files([], exclude) do
    {files, errors, notes} = expand([@default_glob], exclude, false)

    default_notes =
      if files == [],
        do: ["no .heex files matched the default #{@default_glob}" | notes],
        else: notes

    {files, errors, default_notes}
  end

  defp resolve_files(paths, exclude), do: expand(paths, exclude, true)

  defp expand(paths, exclude, explicit?) do
    {matched, errors} = Enum.reduce(paths, {[], []}, &collect_path(&1, &2, explicit?))
    excluded = Enum.flat_map(exclude, &expand_pattern/1)

    files =
      matched
      |> Enum.uniq()
      |> Enum.reject(fn file -> Enum.any?(excluded, &under?(file, &1)) end)
      |> Enum.sort()
      |> Enum.map(&Path.relative_to_cwd/1)

    {files, Enum.reverse(errors), []}
  end

  defp under?(file, excluded), do: file == excluded or String.starts_with?(file, excluded <> "/")

  defp expand_path(path, _explicit?) when not is_binary(path) or path == "",
    do: {:error, "invalid path #{inspect(path)}"}

  defp expand_path(path, explicit?) do
    full = Path.expand(path)

    cond do
      File.dir?(full) ->
        {:ok,
         full
         |> Path.join("**/*.heex")
         |> Path.wildcard()
         |> heex()}

      File.regular?(full) ->
        if Path.extname(full) == ".heex",
          do: {:ok, [full]},
          else: {:error, "#{path} is not a .heex file"}

      glob?(path) ->
        case full
             |> Path.wildcard()
             |> heex() do
          [] when explicit? -> {:error, "no .heex files match #{path}"}
          files -> {:ok, files}
        end

      true ->
        {:error, "#{path} does not exist"}
    end
  end

  defp collect_path(path, {acc, errors}, explicit?) do
    case expand_path(path, explicit?) do
      {:ok, files} -> {files ++ acc, errors}
      {:error, message} -> {acc, [error(:bad_path, message, path) | errors]}
    end
  end

  defp expand_pattern(pattern) do
    pattern
    |> Path.expand()
    |> Path.wildcard()
  end

  defp heex(paths), do: Enum.filter(paths, &(Path.extname(&1) == ".heex" and not File.dir?(&1)))

  defp glob?(path), do: String.contains?(path, ["*", "?", "[", "{"])

  # -- analysis --------------------------------------------------------------

  defp analyse(files, checks, opts) do
    results = for file <- files, do: analyse_file(file, checks, opts)

    {Enum.flat_map(results, &elem(&1, 0)), Enum.flat_map(results, &elem(&1, 1))}
  end

  defp analyse_file(file, checks, opts) do
    case File.read(file) do
      {:ok, raw} -> analyse_text(file, raw, checks, opts)
      {:error, reason} -> {[], [error(:read, "cannot read: #{:file.format_error(reason)}", file)]}
    end
  end

  defp analyse_text(file, raw, checks, opts) do
    if String.valid?(raw) do
      check_file(file, raw, checks, opts)
    else
      {[], [error(:read, "template is not valid UTF-8", file)]}
    end
  end

  defp check_file(file, raw, checks, opts) do
    source_file = Credo.SourceFile.parse(raw, file)

    checks
    |> Enum.map(&run_check(&1, source_file, file, opts))
    |> Enum.reduce({[], []}, fn {f, e}, {fs, es} -> {f ++ fs, e ++ es} end)
  end

  defp run_check(key, source_file, file, opts) do
    {module, param} = Map.fetch!(@checks, key)

    params =
      case Keyword.get(opts, param) do
        values when values in [nil, []] -> []
        values -> [{param, values}]
      end

    issues = module.run(source_file, params)

    findings =
      for issue <- List.wrap(issues) do
        %{check: key, file: file, line: issue.line_no, message: issue.message}
      end

    {findings, []}
  rescue
    exception ->
      {[], [error(:check_failed, "#{key} raised: #{Exception.message(exception)}", file, key)]}
  catch
    kind, reason ->
      {[], [error(:check_failed, "#{key} #{kind}: #{inspect(reason)}", file, key)]}
  end

  defp error(kind, message, file \\ nil, check \\ nil) do
    for {k, v} <- [file: file, check: check], v != nil, into: %{kind: kind, message: message} do
      {k, v}
    end
  end
end
