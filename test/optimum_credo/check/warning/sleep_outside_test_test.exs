defmodule OptimumCredo.Check.Warning.SleepOutsideTestTest do
  use Credo.Test.Case, async: true

  alias OptimumCredo.Check.Warning.SleepOutsideTest

  @source """
  defmodule MyApp.Worker do
    def run do
      Process.sleep(100)
      :timer.sleep(200)
      100 |> Process.sleep()
    end
  end
  """

  test "reports sleeps in production code" do
    @source
    |> to_source_file("lib/my_app/worker.ex")
    |> run_check(SleepOutsideTest)
    |> assert_issues(fn issues -> assert Enum.map(issues, & &1.line_no) == [3, 4, 5] end)
  end

  test "ignores tests, support files and priv by default" do
    for filename <- [
          "test/my_app/worker_test.exs",
          "test/support/helper.ex",
          "priv/repo/seeds.exs",
          "apps/a/test/x_test.exs"
        ] do
      @source
      |> to_source_file(filename)
      |> run_check(SleepOutsideTest)
      |> refute_issues()
    end
  end

  test "ignore_paths is configurable" do
    @source
    |> to_source_file("lib/mix/tasks/wait.ex")
    |> run_check(SleepOutsideTest, ignore_paths: ["lib/mix/tasks/"])
    |> refute_issues()

    @source
    |> to_source_file("test/helper.ex")
    |> run_check(SleepOutsideTest, ignore_paths: [])
    |> assert_issues(fn issues -> assert length(issues) == 3 end)
  end

  test "allows sleeping forever and unrelated calls, strings and comments" do
    ~S'''
    defmodule MyApp.Worker do
      # Process.sleep(1)
      def run do
        Process.sleep(:infinity)
        Task.sleep(100)
        Process.send_after(self(), :go, 100)
        sleep(100)
        "Process.sleep(100)"
      end
    end
    '''
    |> to_source_file("lib/my_app/worker.ex")
    |> run_check(SleepOutsideTest)
    |> refute_issues()
  end

  test "reports Elixir.Process, piped durations and :timer forms; infinity stays allowed" do
    """
    defmodule MyApp.Worker do
      def run(ms) do
        Elixir.Process.sleep(ms)
        ms |> Process.sleep()
        :timer.sleep(ms)
        Process.sleep(:infinity)
        :timer.sleep(:infinity)
        Process.sleep(ms, :extra)
      end
    end
    """
    |> to_source_file("lib/my_app/worker.ex")
    |> run_check(SleepOutsideTest)
    |> assert_issues(fn issues -> assert Enum.map(issues, & &1.line_no) == [3, 4, 5] end)
  end

  test "path patterns match whole directory segments and file suffixes" do
    source = "defmodule A do\n  def run, do: Process.sleep(10)\nend"

    # "contest/" is not the "test/" directory.
    assert [_item] =
             source
             |> to_source_file("lib/contest/worker.ex")
             |> run_check(SleepOutsideTest)

    assert [_item] =
             source
             |> to_source_file("lib/my_app/latest.ex")
             |> run_check(SleepOutsideTest)

    refute_issues(
      source
      |> to_source_file("test/support/helpers.ex")
      |> run_check(SleepOutsideTest)
    )

    refute_issues(
      source
      |> to_source_file("lib/my_app/worker_test.exs")
      |> run_check(SleepOutsideTest)
    )

    refute_issues(
      source
      |> to_source_file("priv/repo/seeds.exs")
      |> run_check(SleepOutsideTest)
    )

    source
    |> to_source_file("lib/my_app/retry/backoff.ex")
    |> run_check(SleepOutsideTest, ignore_paths: ["lib/my_app/retry/"])
    |> refute_issues()
  end

  test "raw .heex files are ignored" do
    "<div>Process.sleep(10)</div>"
    |> Credo.SourceFile.parse("lib/page.html.heex")
    |> run_check(SleepOutsideTest)
    |> refute_issues()
  end
end
