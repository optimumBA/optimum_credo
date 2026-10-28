defmodule OptimumCredo.Check.Warning.LoggerErrorWithoutContextTest do
  use Credo.Test.Case, async: true

  alias OptimumCredo.Check.Warning.LoggerErrorWithoutContext

  test "reports constant messages in rescue, catch and error branches" do
    ~S'''
    defmodule Sample do
      require Logger

      def a(x) do
        work(x)
      rescue
        _ -> Logger.error("work failed")
      end

      def b(x) do
        case work(x) do
          {:ok, v} -> v
          {:error, _reason} -> Logger.error("work failed")
          :error -> Logger.error("failed")
        end
      end

      def c(x) do
        try do
          work(x)
        catch
          :exit, _ -> Logger.error("exited")
        end
      end

      def d(x) do
        with {:ok, v} <- work(x) do
          v
        else
          {:error, reason} when is_atom(reason) -> Logger.error("bad")
        end
      end
    end
    '''
    |> to_source_file()
    |> run_check(LoggerErrorWithoutContext)
    |> assert_issues(fn issues ->
      assert Enum.map(issues, & &1.line_no) == [7, 13, 14, 22, 30]
    end)
  end

  test "allows interpolated, variable, function and metadata messages" do
    ~S'''
    defmodule Sample do
      require Logger

      def a(x) do
        work(x)
      rescue
        e ->
          Logger.error("failed for #{x}: #{inspect(e)}")
          Logger.error(Exception.message(e))
          Logger.error(fn -> "failed" end)
          Logger.error("failed", user_id: x)
          Logger.error("failed" <> inspect(e))
          Logger.warning("failed")
          Logger.info("failed")
      end
    end
    '''
    |> to_source_file()
    |> run_check(LoggerErrorWithoutContext)
    |> refute_issues()
  end

  test "ignores constant messages outside error branches by default" do
    ~S'''
    defmodule Sample do
      require Logger

      def a(x) do
        Logger.error("startup failed")
        case x do
          {:ok, _} -> Logger.error("ok branch")
          _ -> Logger.error("other")
        end
        "Logger.error(\"x\")"
      end
    end
    '''
    |> to_source_file()
    |> run_check(LoggerErrorWithoutContext)
    |> refute_issues()
  end

  test "scope: :all reports every constant message" do
    ~S'''
    defmodule Sample do
      require Logger

      def a(x) do
        Logger.error("startup failed")
        Logger.error("with metadata", id: x)
      end
    end
    '''
    |> to_source_file()
    |> run_check(LoggerErrorWithoutContext, scope: :all)
    |> assert_issue(fn issue -> assert issue.line_no == 5 end)
  end

  test "reports piped constant messages and empty metadata, not metadata or interpolation" do
    ~S'''
    defmodule Sample do
      require Logger

      def run(result, metadata) do
        case result do
          {:error, _} -> "failed" |> Logger.error()
          {:error, _} -> Logger.error("failed", [])
          {:error, reason} -> Logger.error("failed", reason: reason)
          {:error, _} -> Logger.error("failed", metadata)
          {:error, reason} -> Logger.error("failed: #{inspect(reason)}")
          {:error, reason} -> Logger.error("failed: " <> inspect(reason))
          {:error, _} -> Logger.error(fn -> "failed" end)
          {:ok, _} -> Logger.error("not an error branch")
        end
      end
    end
    '''
    |> to_source_file()
    |> run_check(LoggerErrorWithoutContext)
    |> assert_issues(fn issues -> assert Enum.map(issues, & &1.line_no) == [6, 7] end)
  end

  test "a bare constant message after Logger.metadata/1 is still reported (documented limit)" do
    """
    defmodule Sample do
      require Logger

      def run(id, result) do
        Logger.metadata(id: id)

        case result do
          :error -> Logger.error("sync failed")
          _ -> :ok
        end
      end
    end
    """
    |> to_source_file()
    |> run_check(LoggerErrorWithoutContext)
    |> assert_issue(fn issue -> assert issue.line_no == 8 end)
  end

  test "reports in nested anonymous functions and with-else clauses, not other levels" do
    """
    defmodule Sample do
      require Logger

      def run(items) do
        Enum.each(items, fn
          {:error, _} -> Logger.error("item failed")
          _ -> Logger.error("item odd")
        end)

        with {:ok, _} <- items do
          :ok
        else
          {:error, _} -> Logger.error("with failed")
        end

        Logger.warning("not an error")
        Logger.info("fine")
      end
    end
    """
    |> to_source_file()
    |> run_check(LoggerErrorWithoutContext)
    |> assert_issues(fn issues -> assert Enum.map(issues, & &1.line_no) == [6, 13] end)
  end
end
