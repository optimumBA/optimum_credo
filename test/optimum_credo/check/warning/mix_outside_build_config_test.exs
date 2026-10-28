defmodule OptimumCredo.Check.Warning.MixOutsideBuildConfigTest do
  use Credo.Test.Case, async: true

  alias OptimumCredo.Check.Warning.MixOutsideBuildConfig

  defp run(source, params \\ [], path \\ "lib/my_app/mailer.ex") do
    source
    |> to_source_file(path)
    |> run_check(MixOutsideBuildConfig, params)
  end

  test "it reports Mix.env and other Mix calls in lib" do
    for call <- [
          "if Mix.env() == :prod, do: :ok",
          "Mix.Project.config()",
          "Mix.shell().info(\"x\")",
          "Mix.Task.run(\"app.start\")"
        ] do
      "defmodule MyApp.Mailer do\n  def f, do: #{call}\nend\n"
      |> run()
      |> assert_issue()
    end
  end

  test "it reports the line and call" do
    """
    defmodule MyApp.Mailer do
      def env do
        Mix.env()
      end
    end
    """
    |> run()
    |> assert_issue(fn issue ->
      assert issue.line_no == 3
      assert issue.trigger == "Mix.env"
    end)
  end

  test "it reports Mix in config/runtime.exs but not in other config files" do
    source = "import Config\nif Mix.env() == :prod, do: :ok\n"

    source
    |> run([], "config/runtime.exs")
    |> assert_issue()

    source
    |> run([], "config/config.exs")
    |> refute_issues()

    source
    |> run([], "config/dev.exs")
    |> refute_issues()

    source
    |> run([], "config/test.exs")
    |> refute_issues()

    source
    |> run([], "config/prod.exs")
    |> refute_issues()

    source
    |> run([], "mix.exs")
    |> refute_issues()

    source
    |> run([], "test/support/helper.ex")
    |> refute_issues()
  end

  test "it allows Mix tasks by path, by module name and by allowed_paths" do
    source = "defmodule Mix.Tasks.Seed do\n  def run(_), do: Mix.shell().info(\"x\")\nend\n"

    source
    |> run([], "lib/mix/tasks/seed.ex")
    |> refute_issues()

    source
    |> run([], "lib/my_app/tasks/seed.ex")
    |> refute_issues()

    other = "defmodule MyApp.Seed do\n  def run, do: Mix.shell().info(\"x\")\nend\n"

    other
    |> run([], "lib/my_app/tasks/seed.ex")
    |> assert_issue()

    other
    |> run([allowed_paths: ["lib/my_app/tasks"]], "lib/my_app/tasks/seed.ex")
    |> refute_issues()

    other
    |> run([allowed_paths: []], "lib/mix/tasks/seed.ex")
    |> assert_issue()
  end

  test "it accepts calls guarded by Code.ensure_loaded?(Mix)" do
    source = """
    defmodule MyApp.Env do
      def env do
        if Code.ensure_loaded?(Mix), do: Mix.env(), else: :prod
      end

      def test? do
        Code.ensure_loaded?(Mix) and Mix.env() == :test
      end

      def other, do: function_exported?(Mix, :env, 0) && Mix.env()
    end
    """

    source
    |> run()
    |> refute_issues()

    source
    |> run(allow_ensure_loaded_guard: false)
    |> assert_issues()
  end

  test "an unrelated guard does not accept the call" do
    "defmodule A do\n  def f, do: if(Code.ensure_loaded?(Jason), do: Mix.env())\nend\n"
    |> run()
    |> assert_issue()
  end

  test "it ignores use, behaviour, aliases, strings, comments and lookalike modules" do
    """
    defmodule MyApp.Task do
      use Mix.Task
      @behaviour Mix.Task
      alias Mix.Tasks.Compile
      # Mix.env()
      def a, do: "Mix.env()"
      def b, do: MyApp.Mix.env()
      def c, do: Mixer.env()
    end
    """
    |> run()
    |> refute_issues()
  end

  describe "review regressions" do
    test "it follows an alias of a Mix module" do
      """
      defmodule MyApp.Mailer do
        alias Mix.Project

        def f, do: Project.config()
      end
      """
      |> run()
      |> assert_issue(fn issue ->
        assert issue.trigger == "Mix.Project.config"
        assert issue.line_no == 4
      end)
    end

    test "an unrelated module aliased as Mix is not Mix" do
      """
      defmodule MyApp.Mailer do
        alias MyApp.Tools, as: Mix

        def f, do: Mix.env()
      end
      """
      |> run()
      |> refute_issues()
    end

    test "a Code.ensure_loaded? guard on a Mix submodule is accepted" do
      """
      defmodule MyApp.Mailer do
        def f do
          if Code.ensure_loaded?(Mix.Project), do: Mix.Project.config()
        end
      end
      """
      |> run()
      |> refute_issues()
    end

    test "Mix in strings, comments and use Mix.Task is not a call" do
      """
      defmodule MyApp.Mailer do
        # Mix.env() is unavailable
        @moduledoc "do not call Mix.env()"
        @behaviour Mix.Task
      end
      """
      |> run()
      |> refute_issues()
    end
  end
end
