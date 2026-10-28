defmodule Mix.Tasks.Optimum.HeexCheckTest do
  use ExUnit.Case, async: false

  alias Mix.Tasks.Optimum.HeexCheck

  @bad ~s(<img src="/images/logo.png" />\n<button phx-click="save-draft" />\n)

  setup do
    dir = Path.join(System.tmp_dir!(), "heex_task_#{System.unique_integer([:positive])}")

    dir
    |> Path.join("lib")
    |> File.mkdir_p!()

    old = File.cwd!()
    File.cd!(dir)

    on_exit(fn ->
      File.cd!(old)
      File.rm_rf!(dir)
    end)
  end

  test "findings exit 1 with text output and lines" do
    File.write!("lib/a.heex", @bad)
    {status, out} = HeexCheck.execute([])
    assert status == 1
    assert out =~ "lib/a.heex:1: [HardcodedAssetPath]"
    assert out =~ "lib/a.heex:2: [EventNameSnakeCase]"
    assert out =~ "1 file(s) checked, 2 finding(s), 0 error(s)"
  end

  test "clean run exits 0" do
    File.write!("lib/a.heex", "<p>hi</p>")
    assert {0, out} = HeexCheck.execute(["lib"])
    assert out =~ "0 finding(s)"
  end

  test "empty default match is visible and exits 0" do
    assert {0, out} = HeexCheck.execute([])
    assert out =~ "note: no .heex files matched"
  end

  test "--advisory suppresses only the findings exit" do
    File.write!("lib/a.heex", @bad)
    assert {0, _value} = HeexCheck.execute(["--advisory"])
    assert {2, out} = HeexCheck.execute(["--advisory", "missing.heex"])
    assert out =~ "missing.heex does not exist"
  end

  test "json output is valid and structured" do
    File.write!("lib/a.heex", @bad)
    {1, out} = HeexCheck.execute(["--format", "json", "--checks", "hardcoded_asset_path"])

    assert %{
             "files" => ["lib/a.heex"],
             "findings" => [
               %{"check" => "HardcodedAssetPath", "line" => 1, "file" => "lib/a.heex"}
             ],
             "errors" => [],
             "notes" => []
           } = Jason.decode!(out)
  end

  test "json errors carry kind as string" do
    {2, out} = HeexCheck.execute(["--format", "json", "nope.heex"])
    assert %{"errors" => [%{"kind" => "bad_path"}]} = Jason.decode!(out)
  end

  test "repeatable --exclude, --checks, --prefix, --allowed-*" do
    File.write!("lib/a.heex", @bad)
    File.write!("lib/b.heex", @bad)
    {1, out} = HeexCheck.execute(["--exclude", "lib/b.heex", "--exclude", "nothing"])
    refute out =~ "lib/b.heex"

    assert {1, out} =
             HeexCheck.execute([
               "--checks",
               "event_name_snake_case",
               "--checks",
               "hidden_id_input"
             ])

    refute out =~ "HardcodedAssetPath"

    assert {0, out} = HeexCheck.execute(["--prefix", "/other/", "--allowed-event", "save-draft"])
    assert out =~ "0 finding(s)"
  end

  test "usage errors exit 2" do
    assert {2, out} = HeexCheck.execute(["--bogus"])
    assert out =~ "invalid option"
    assert {2, out} = HeexCheck.execute(["--format", "xml"])
    assert out =~ "unsupported format"
    assert {2, out} = HeexCheck.execute(["--checks", "Nope"])
    assert out =~ "unknown check"
    assert {2, _value} = HeexCheck.execute(["--format"])
  end

  test "run/1 prints through Mix.shell and returns :ok when clean" do
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(Mix.Shell.IO) end)
    File.write!("lib/a.heex", "<p>hi</p>")
    assert :ok = HeexCheck.run([])
    assert_received {:mix_shell, :info, [msg]}
    assert msg =~ "1 file(s) checked"
  end

  test "an explicitly empty checks selection is a usage error" do
    assert {2, out} = HeexCheck.execute(["--checks", ""])
    assert out =~ "no checks selected"
  end
end
