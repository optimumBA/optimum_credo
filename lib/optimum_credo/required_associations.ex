defmodule OptimumCredo.RequiredAssociations do
  @moduledoc false

  alias OptimumCredo.OptimumIdiomsSupport
  alias OptimumCredo.TestsSupport

  @spec externally_set(String.t(), String.t()) :: %{String.t() => MapSet.t(String.t())}
  def externally_set(filename, migrations_path) do
    directory =
      filename
      |> Path.expand()
      |> Path.dirname()

    case project_root(directory, migrations_path) do
      nil -> %{}
      root -> collect_project(root)
    end
  end

  defp project_root(directory, migrations_path) do
    parent = Path.dirname(directory)

    migrations? =
      directory
      |> Path.join(migrations_path)
      |> File.dir?()

    cond do
      migrations? -> directory
      parent == directory -> nil
      true -> project_root(parent, migrations_path)
    end
  end

  defp collect_project(root) do
    root
    |> Path.join("lib/**/*.ex")
    |> Path.wildcard()
    |> Enum.reduce(%{}, &collect_file/2)
  end

  defp collect_file(path, associations) do
    with {:ok, text} <- File.read(path),
         {:ok, ast} <- Code.string_to_quoted(text, emit_warnings: false) do
      ast
      |> OptimumIdiomsSupport.unpipe()
      |> TestsSupport.walk_env(associations, &collect/3)
    else
      _unreadable_or_invalid -> associations
    end
  end

  defp collect(node, env, associations) do
    case TestsSupport.call(node, env) do
      %{module: "Ecto.Changeset", fun: :put_assoc, args: [input, field, _value]}
      when is_atom(field) and field not in [nil, true, false] ->
        case changeset_module(input, env) do
          nil ->
            {:cont, associations}

          module ->
            {:cont,
             Map.update(
               associations,
               module,
               MapSet.new([Atom.to_string(field)]),
               &MapSet.put(&1, Atom.to_string(field))
             )}
        end

      _other ->
        {:cont, associations}
    end
  end

  defp changeset_module(input, env) do
    case TestsSupport.call(input, env) do
      %{module: "Ecto.Changeset", args: [inner | _rest]} -> changeset_module(inner, env)
      %{module: module, fun: :changeset} when is_binary(module) -> module
      _unknown -> nil
    end
  end
end
