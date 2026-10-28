defmodule OptimumCredo.UnloadedImportTest do
  use ExUnit.Case, async: false

  alias OptimumCredo.TestsSupport

  @tag :tmp_dir
  test "installed imports retain exact exports without loading source-derived module names", %{
    tmp_dir: dir
  } do
    name = "CredoUnloadedImport#{System.unique_integer([:positive])}"
    source = Path.join(dir, "import_fixture.ex")
    sentinel = Path.join(dir, "loaded")

    File.write!(source, """
    defmodule #{name} do
      @on_load :loaded
      def loaded, do: File.write!(#{inspect(sentinel)}, "loaded")
      def assert_custom(value), do: value
      defmacro assert_custom_macro(value), do: value
    end
    """)

    compiler = System.find_executable("elixirc")

    cleared_env =
      System.get_env()
      |> Map.drop(~w(PATH HOME TMPDIR LANG ERL_FLAGS))
      |> Enum.map(fn {name, _value} -> {name, nil} end)

    {output, status} = System.cmd(compiler, ["-o", dir, source], env: cleared_env)
    assert status == 0, output
    File.rm(sentinel)
    outside = %{module: ":" <> Path.join(dir, "Elixir." <> name), only: nil, except: []}
    refute TestsSupport.provides?(outside, :assert_custom, [1])
    Code.prepend_path(dir)

    try do
      assert_raise ArgumentError, fn -> String.to_existing_atom("Elixir." <> name) end
      spec = %{module: name, only: nil, except: []}
      assert TestsSupport.provides?(spec, :assert_custom, [1])
      assert TestsSupport.provides?(spec, :assert_custom_macro, [1])
      refute TestsSupport.provides?(spec, :assert_custom, [2])
      refute File.exists?(sentinel)

      refute TestsSupport.provides?(%{spec | except: [assert_custom: 1]}, :assert_custom, [1])
    after
      Code.delete_path(dir)
    end
  end
end
