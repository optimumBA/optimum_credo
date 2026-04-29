defmodule OptimumCredo.Check.Warning.RuntimeEnvDevDefaultTest do
  use Credo.Test.Case

  alias OptimumCredo.Check.Warning.RuntimeEnvDevDefault

  test "it should report System.get_env with /Users/ default in config/runtime.exs" do
    """
    codegen_dir = System.get_env("CODEGEN_DIR", "/Users/me/codegen")
    """
    |> to_source_file("config/runtime.exs")
    |> run_check(RuntimeEnvDevDefault)
    |> assert_issue(fn issue ->
      assert issue.message =~ "/Users/me/codegen"
    end)
  end

  test "it should report System.get_env with /home/ default in config/runtime.exs" do
    """
    base_dir = System.get_env("BASE_DIR", "/home/deploy/app")
    """
    |> to_source_file("config/runtime.exs")
    |> run_check(RuntimeEnvDevDefault)
    |> assert_issue(fn issue ->
      assert issue.message =~ "/home/deploy/app"
    end)
  end

  test "it should report System.get_env with ~/ default in config/runtime.exs" do
    """
    config_path = System.get_env("CONFIG_PATH", "~/config/app.exs")
    """
    |> to_source_file("config/runtime.exs")
    |> run_check(RuntimeEnvDevDefault)
    |> assert_issue(fn issue ->
      assert issue.message =~ "~/config/app.exs"
    end)
  end

  test "it should NOT report System.get_env with a production default string" do
    """
    pool_size = System.get_env("POOL_SIZE", "10")
    """
    |> to_source_file("config/runtime.exs")
    |> run_check(RuntimeEnvDevDefault)
    |> refute_issues()
  end

  test "it should NOT report System.get_env with no default" do
    """
    codegen_dir = System.get_env("CODEGEN_DIR")
    """
    |> to_source_file("config/runtime.exs")
    |> run_check(RuntimeEnvDevDefault)
    |> refute_issues()
  end

  test "it should NOT report System.get_env || fallback (not a literal default)" do
    """
    codegen_dir = System.get_env("CODEGEN_DIR") || "/Users/me/fallback"
    """
    |> to_source_file("config/runtime.exs")
    |> run_check(RuntimeEnvDevDefault)
    |> refute_issues()
  end

  test "it should NOT report System.get_env with /Users/ default in config/dev.exs" do
    """
    codegen_dir = System.get_env("CODEGEN_DIR", "/Users/me/codegen")
    """
    |> to_source_file("config/dev.exs")
    |> run_check(RuntimeEnvDevDefault)
    |> refute_issues()
  end

  test "it should NOT report System.get_env with /Users/ default in a lib file" do
    """
    defmodule MyModule do
      def get_dir do
        System.get_env("DIR", "/Users/me/dir")
      end
    end
    """
    |> to_source_file("lib/my_module.ex")
    |> run_check(RuntimeEnvDevDefault)
    |> refute_issues()
  end

  test "it should report the correct line number" do
    """
    import Config

    codegen_dir = System.get_env("CODEGEN_DIR", "/Users/me/codegen")
    """
    |> to_source_file("config/runtime.exs")
    |> run_check(RuntimeEnvDevDefault)
    |> assert_issue(fn issue ->
      assert issue.line_no == 3
    end)
  end
end
