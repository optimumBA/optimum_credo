defmodule OptimumCredo.Check.Warning.SleepInTestTest do
  use Credo.Test.Case, async: true

  alias OptimumCredo.Check.Warning.SleepInTest

  @file_name "test/my_app/thing_test.exs"

  defp run(code, params \\ [], file \\ @file_name) do
    code
    |> to_source_file(file)
    |> run_check(SleepInTest, params)
  end

  test "reports Process.sleep and :timer.sleep, including piped" do
    """
    defmodule ThingTest do
      use ExUnit.Case
      test "a" do
        Process.sleep(200)
        :timer.sleep(10)
        100 |> Process.sleep()
      end
    end
    """
    |> run()
    |> assert_issues(fn issues -> assert length(issues) == 3 end)
  end

  test "ignores non-test files" do
    """
    defmodule Thing do
      def a, do: Process.sleep(200)
    end
    """
    |> run([], "lib/my_app/thing.ex")
    |> refute_issues()
  end

  test "ignores lookalikes, strings, quotes and aliased other modules" do
    """
    defmodule ThingTest do
      use ExUnit.Case
      test "a" do
        Task.sleep(1)
        MyProcess.sleep(1)
        assert "Process.sleep(1)" == "x"
        quote do
          Process.sleep(5)
        end
      end
    end
    """
    |> run()
    |> refute_issues()
  end

  test "exempts files with @moduletag :timing" do
    """
    defmodule ThingTest do
      use ExUnit.Case
      @moduletag :timing
      test "a", do: Process.sleep(1)
    end
    """
    |> run()
    |> refute_issues()
  end

  test "exempt_moduletag nil disables the exemption" do
    """
    defmodule ThingTest do
      use ExUnit.Case
      @moduletag :timing
      test "a", do: Process.sleep(1)
    end
    """
    |> run(exempt_moduletag: false)
    |> assert_issue()
  end

  test "functions param customises the list" do
    """
    defmodule ThingTest do
      use ExUnit.Case
      test "a" do
        Process.sleep(1)
        MyApp.Wait.pause(1)
      end
    end
    """
    |> run(functions: [{MyApp.Wait, :pause}])
    |> assert_issue(fn issue -> assert issue.line_no == 5 end)
  end

  test "flags long wait blocks only above the threshold" do
    code = """
    defmodule ThingTest do
      use ExUnit.Case
      test "a" do
        wait_until(fn ->
          a = 1
          b = 2
          c = 3
          assert a + b + c == 6
        end)
        wait_until(fn -> assert true end)
      end
    end
    """

    code
    |> run()
    |> assert_issue(fn issue -> assert issue.line_no == 4 end)

    code
    |> run(max_wait_block_lines: 10)
    |> refute_issues()
  end

  test "resolves aliased and imported receivers and literal apply" do
    """
    defmodule ThingTest do
      use ExUnit.Case
      alias Process, as: P
      import :timer, only: [sleep: 1]

      test "a" do
        P.sleep(10)
        sleep(20)
        apply(Process, :sleep, [30])
      end
    end
    """
    |> run()
    |> assert_issues(fn issues -> assert Enum.map(issues, & &1.line_no) == [7, 8, 9] end)
  end

  test "an alias in one module does not leak into a sibling module" do
    """
    defmodule AThingTest do
      use ExUnit.Case
      alias MyApp.Process
      test "a", do: Process.sleep(10)
    end

    defmodule BThingTest do
      use ExUnit.Case
      test "b", do: Process.sleep(10)
    end
    """
    |> run()
    |> assert_issue(fn issue -> assert issue.line_no == 9 end)
  end

  test "a local alias that shadows Process is not the stdlib module" do
    """
    defmodule ThingTest do
      use ExUnit.Case
      alias MyApp.Clock, as: Process
      test "a", do: Process.sleep(10)
    end
    """
    |> run()
    |> refute_issues()
  end

  test "sleep(:infinity) parks a process and is not a delay" do
    """
    defmodule ThingTest do
      use ExUnit.Case
      test "a" do
        spawn(fn -> Process.sleep(:infinity) end)
        Process.sleep(1)
      end
    end
    """
    |> run()
    |> assert_issue(fn issue -> assert issue.line_no == 5 end)
  end

  test "an imported function that is not in the only list is not a sleep" do
    """
    defmodule ThingTest do
      use ExUnit.Case
      import :timer, only: [seconds: 1]
      test "a", do: sleep(10)
    end
    """
    |> run()
    |> refute_issues()
  end

  test "a sleep inside a recursive polling helper is a back-off, not a fixed wait" do
    """
    defmodule ThingTest do
      use ExUnit.Case
      test "a", do: wait_for(3)

      defp wait_for(0), do: flunk("timeout")

      defp wait_for(retries) do
        if not ready?() do
          Process.sleep(50)
          wait_for(retries - 1)
        end
      end

      defp pause, do: Process.sleep(50)
    end
    """
    |> run()
    |> assert_issue(fn issue -> assert issue.line_no == 14 end)
  end
end
