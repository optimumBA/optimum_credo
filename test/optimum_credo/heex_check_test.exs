defmodule OptimumCredo.HeexCheckTest do
  use ExUnit.Case, async: false

  alias OptimumCredo.HeexCheck

  @bad """
  <div>
    <img src="/images/logo.png" />
    <input type="hidden" name="user_id" value="1" />
    <button phx-click="save-draft">Save</button>
  </div>
  """

  setup do
    dir = Path.join(System.tmp_dir!(), "heex_check_#{System.unique_integer([:positive])}")

    dir
    |> Path.join("lib/web/nested")
    |> File.mkdir_p!()

    on_exit(fn -> File.rm_rf!(dir) end)
    old = File.cwd!()
    File.cd!(dir)
    on_exit(fn -> File.cd!(old) end)
    {:ok, dir: dir}
  end

  defp write(path, content), do: File.write!(path, content)
  defp checks(result), do: Enum.map(result.findings, &{&1.check, &1.line})

  test "default glob finds all three checks with accurate lines and paths" do
    write("lib/web/a.heex", @bad)
    result = HeexCheck.run([])

    assert result.errors == []
    assert result.files == ["lib/web/a.heex"]

    assert checks(result) ==
             Enum.sort_by(
               [{"EventNameSnakeCase", 4}, {"HardcodedAssetPath", 2}, {"HiddenIdInput", 3}],
               fn {c, l} -> {l, c} end
             )

    assert Enum.all?(result.findings, &(&1.file == "lib/web/a.heex"))
  end

  test "clean templates produce no findings" do
    write(
      "lib/web/ok.heex",
      ~s(<img src={~p"/images/a.png"} />\n<button phx-click="save_draft" />)
    )

    result = HeexCheck.run([])
    assert %{findings: [], errors: [], files: ["lib/web/ok.heex"]} = result
  end

  test "default glob matching nothing is a visible note, not an error" do
    result = HeexCheck.run([])
    assert result.errors == [] and result.files == []
    assert [note] = result.notes
    assert note =~ "lib/**/*.heex"
  end

  test "directories recurse, non-heex files are ignored, results sorted and deduplicated" do
    write("lib/web/nested/b.heex", @bad)
    write("lib/web/a.heex", @bad)
    write("lib/web/a.html", @bad)
    result = HeexCheck.run(["lib", "lib/web/a.heex", "lib/**/*.heex"])
    assert result.files == ["lib/web/a.heex", "lib/web/nested/b.heex"]
    assert length(result.findings) == 6
    assert result.findings == Enum.sort_by(result.findings, &{&1.file, &1.line, &1.check})
  end

  test "exclude removes files, globs and directories" do
    write("lib/web/nested/b.heex", @bad)
    write("lib/web/a.heex", @bad)
    assert HeexCheck.run([], exclude: ["lib/web/nested"]).files == ["lib/web/a.heex"]
    assert HeexCheck.run([], exclude: ["lib/web/a.*"]).files == ["lib/web/nested/b.heex"]
    assert HeexCheck.run([], exclude: ["lib/**/*.heex"]).files == []
  end

  test "checks selection accepts snake, camel and qualified names" do
    write("lib/web/a.heex", @bad)

    for name <- ["hidden_id_input", "HiddenIdInput", "OptimumCredo.Check.Warning.HiddenIdInput"] do
      assert []
             |> HeexCheck.run(checks: [name])
             |> checks() == [{"HiddenIdInput", 3}]
    end

    assert []
           |> HeexCheck.run(checks: ["hidden_id_input", "hardcoded_asset_path"])
           |> checks() ==
             [{"HardcodedAssetPath", 2}, {"HiddenIdInput", 3}]
  end

  test "unknown check names and options are errors and nothing runs" do
    write("lib/web/a.heex", @bad)
    result = HeexCheck.run([], checks: ["nope", "String"])
    assert result.findings == []
    assert [%{kind: :unknown_check}, %{kind: :unknown_check}] = result.errors

    assert [%{kind: :bad_option}] = HeexCheck.run([], bogus: 1).errors
    assert [%{kind: :bad_option}] = HeexCheck.run([], prefixes: "/x").errors
    assert [%{kind: :bad_option}] = HeexCheck.run([], checks: "all").errors
    assert [%{kind: :unknown_check}] = HeexCheck.run([], checks: []).errors
  end

  test "does not create atoms for unknown check names" do
    name = "definitely_new_check_#{System.unique_integer([:positive])}"
    assert [%{kind: :unknown_check}] = HeexCheck.run([], checks: [name]).errors
    assert_raise ArgumentError, fn -> String.to_existing_atom(name) end
  end

  test "params: prefixes, allowed fields and allowed events" do
    write("lib/web/a.heex", @bad)

    assert []
           |> HeexCheck.run(prefixes: ["/other/"])
           |> checks()
           |> Enum.map(&elem(&1, 0)) ==
             ["HiddenIdInput", "EventNameSnakeCase"]

    assert [{"HardcodedAssetPath", 2}] ==
             []
             |> HeexCheck.run(allowed_fields: ["user_id"], allowed_events: ["save-draft"])
             |> checks()
  end

  test "explicit missing path, glob without matches and wrong extension are errors" do
    write("lib/web/a.html", "x")
    write("lib/web/a.heex", @bad)
    result = HeexCheck.run(["lib/missing.heex", "nothing/**/*.heex", "lib/web/a.html"])
    assert [%{kind: :bad_path, message: m1}, %{message: m2}, %{message: m3}] = result.errors
    assert m1 =~ "does not exist" or m2 =~ "does not exist" or m3 =~ "does not exist"
    assert Enum.any?(result.errors, &(&1.message =~ "no .heex files match"))
    assert Enum.any?(result.errors, &(&1.message =~ "not a .heex file"))
    assert result.findings == []
  end

  test "good paths are still checked when another explicit path errors" do
    write("lib/web/a.heex", @bad)
    result = HeexCheck.run(["lib/web/a.heex", "gone.heex"])
    assert [%{kind: :bad_path, file: "gone.heex"}] = result.errors
    assert length(result.findings) == 3
  end

  test "unreadable files are read errors" do
    write("lib/web/a.heex", @bad)
    File.chmod!("lib/web/a.heex", 0o000)

    on_exit(fn ->
      "lib/web/a.heex"
      |> Path.expand()
      |> File.chmod(0o644)
    end)

    unless File.read("lib/web/a.heex") != {:error, :eacces} do
      result = HeexCheck.run([])
      assert [%{kind: :read, file: "lib/web/a.heex"}] = result.errors
      assert result.findings == []
    end
  end

  test "symlinked templates are followed" do
    write("real.heex", @bad)
    File.ln_s!("../../real.heex", "lib/web/link.heex")
    result = HeexCheck.run([])
    assert result.files == ["lib/web/link.heex"]
    assert length(result.findings) == 3
  end

  test "raw heex is not parsed as Elixir: unbalanced and non-elixir markup works" do
    write("lib/web/a.heex", ~s(<%= if @x do %>\n<img src="/images/a.png">\n<% end ))
    result = HeexCheck.run([])
    assert result.errors == []
    assert checks(result) == [{"HardcodedAssetPath", 2}]
  end

  test "findings inside comments and script bodies are not reported" do
    write(
      "lib/web/a.heex",
      ~s(<!-- <img src="/images/a.png"> -->\n<script>var a = '<img src="/images/b.png">'</script>)
    )

    assert HeexCheck.run([]).findings == []
  end

  test "invalid excludes are returned as option errors before filesystem expansion" do
    assert %{files: [], findings: [], errors: [%{kind: :bad_option}]} =
             HeexCheck.run([], exclude: 42)

    assert %{errors: [%{kind: :bad_option}]} = HeexCheck.run([], exclude: [42])
  end

  test "invalid UTF-8 template bytes are a read error rather than a clean template" do
    write("lib/web/invalid.heex", <<255, 254>>)
    assert %{findings: [], errors: [%{kind: :read, message: message}]} = HeexCheck.run([])
    assert message =~ "UTF-8"
  end

  test "a dangling matched symlink is surfaced as a read error" do
    File.ln_s!("absent-target.heex", "lib/web/broken.heex")
    assert %{files: ["lib/web/broken.heex"], errors: [%{kind: :read}]} = HeexCheck.run([])
  end
end
