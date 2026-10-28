defmodule OptimumCredo.Check.Readability.BannedAbbreviationsTest do
  use Credo.Test.Case, async: true

  alias OptimumCredo.Check.Readability.BannedAbbreviations

  defp run(source, params \\ []) do
    source
    |> to_source_file()
    |> run_check(BannedAbbreviations, params)
  end

  test "reports function names, parameters and variables with suggestions" do
    """
    defmodule Demo do
      def send_msg(usr, cfg) do
        tmp = build(usr)
        deliver(tmp, cfg)
      end
    end
    """
    |> run()
    |> assert_issues(fn issues ->
      messages = Enum.map(issues, & &1.message)
      assert Enum.any?(messages, &(&1 =~ "msg in send_msg; use message"))
      assert Enum.any?(messages, &(&1 =~ "usr in usr; use user"))
      assert Enum.any?(messages, &(&1 =~ "cfg in cfg; use config"))
      assert Enum.any?(messages, &(&1 =~ "tmp in tmp; use temporary"))
      assert length(issues) == 4
    end)
  end

  test "matches whole underscore segments including prefixes and ? or ! suffixes" do
    """
    defmodule Demo do
      def valid_msg?(_input), do: true
      defp _usr_cache!(_input), do: :ok
      @msg_limit 10
    end
    """
    |> run()
    |> assert_issues(fn issues -> assert Enum.map(issues, & &1.line_no) == [2, 3, 4] end)
  end

  test "reports clause patterns in fn, case, with and for" do
    """
    defmodule Demo do
      def run(list) do
        Enum.map(list, fn {:ok, btn} -> btn end)
        case list do
          [mgr | _] -> mgr
        end
        for idx <- list, do: idx
        with {:ok, qty} <- fetch(list), do: qty
      end
    end
    """
    |> run()
    |> assert_issues(fn issues -> assert Enum.map(issues, & &1.line_no) == [3, 5, 7, 8] end)
  end

  test "does not report uses, pins, atoms, strings, keys, cond conditions or whole-word lookalikes" do
    ~S'''
    defmodule Demo do
      @moduledoc "msg usr cfg"
      def run(message, user) do
        _ = ^user = user
        _ = Map.get(%{msg: 1}, :msg)
        _ = "msg"
        _ = message
        cond do
          message == :tmp -> :ok
          true -> :error
        end
        description = message
        imsg = description
        {description, imsg}
      end
    end
    '''
    |> run()
    |> refute_issues()
  end

  test "banned_abbreviations accepts keyword, map and plain lists and replaces the defaults" do
    source = "defmodule Demo do\n  def run(msg, req), do: {msg, req}\nend"

    source
    |> run(banned_abbreviations: [req: "request"])
    |> assert_issue(fn issue -> assert issue.message =~ "req in req; use request" end)

    source
    |> run(banned_abbreviations: %{"req" => nil, msg: "message"})
    |> assert_issues(fn issues -> assert length(issues) == 2 end)

    source
    |> run(banned_abbreviations: ["req"])
    |> assert_issue(fn issue -> refute issue.message =~ "use " end)
  end

  test "allowed_names accepts complete names" do
    "defmodule Demo do\n  def run(msg, usr), do: {msg, usr}\nend"
    |> run(allowed_names: [:msg])
    |> assert_issue(fn issue -> assert issue.message =~ "usr" end)
  end

  test "checks every parameter of a guarded anonymous function and case clause" do
    """
    defmodule Demo do
      def run(list) do
        Enum.reduce(list, 0, fn msg, count when is_integer(count) -> count + msg end)
        Enum.reduce(list, 0, fn item, tmp when is_integer(tmp) -> tmp + item end)
        case list do
          [usr | _rest] when is_atom(usr) -> usr
        end
      end
    end
    """
    |> to_source_file()
    |> run_check(BannedAbbreviations)
    |> assert_issues(fn issues ->
      assert Enum.map(issues, & &1.line_no) == [3, 4, 6]
    end)
  end

  test "reports a guarded function head parameter but not guard-only uses" do
    """
    defmodule Demo do
      def run(count, other) when is_integer(count) and other > tmp_limit(), do: count
    end
    """
    |> to_source_file()
    |> run_check(BannedAbbreviations)
    |> refute_issues()

    """
    defmodule Demo do
      def run(count, msg) when is_integer(count), do: count
    end
    """
    |> to_source_file()
    |> run_check(BannedAbbreviations)
    |> assert_issue(fn issue -> assert issue.message =~ "message" end)
  end

  test "an invalid banned_abbreviations value raises instead of disabling the check" do
    assert_raise ArgumentError, ~r/invalid banned_abbreviations/, fn ->
      "defmodule A do\nend"
      |> to_source_file()
      |> BannedAbbreviations.run(banned_abbreviations: "msg")
    end
  end

  test "reports with, for, and pin-free map pattern variables" do
    """
    defmodule Demo do
      def run(params, existing) do
        with %{"cfg" => cfg} <- params, ^existing <- cfg do
          for idx <- 1..3, do: idx
        end
      end
    end
    """
    |> to_source_file()
    |> run_check(BannedAbbreviations)
    |> assert_issues(fn issues ->
      assert Enum.map(issues, & &1.line_no) == [3, 4]
    end)
  end
end
