defmodule OptimumCredo.Check.Readability.TypespecOrderTest do
  use Credo.Test.Case

  alias OptimumCredo.Check.Readability.TypespecOrder

  test "it should NOT report properly ordered typespecs" do
    """
    defmodule CredoSampleModule do
      @type apple :: String.t()
      @type banana :: String.t()
      @type cherry :: String.t()

      @typep color :: String.t()
      @typep dimension :: integer()

      @opaque internal :: any()
      @opaque secret :: map()
    end
    """
    |> to_source_file()
    |> run_check(TypespecOrder)
    |> refute_issues()
  end

  test "it should report typespecs that are out of order within the same group" do
    """
    defmodule CredoSampleModule do
      @type cherry :: String.t()
      @type banana :: String.t()
      @type apple :: String.t()
    end
    """
    |> to_source_file()
    |> run_check(TypespecOrder)
    |> assert_issues()
  end

  test "it should report typep specs that are out of order within their group" do
    """
    defmodule CredoSampleModule do
      @type apple :: String.t()
      @type banana :: String.t()

      @typep dimension :: integer()
      @typep color :: String.t()
    end
    """
    |> to_source_file()
    |> run_check(TypespecOrder)
    |> assert_issue()
  end

  test "it reports issues in each group separately" do
    """
    defmodule CredoSampleModule do
      @type zebra :: String.t()
      @type yak :: String.t()

      @type banana :: String.t()
      @type apple :: String.t()
    end
    """
    |> to_source_file()
    |> run_check(TypespecOrder)
    |> assert_issues(fn issues ->
      assert Enum.count(issues) == 2
      assert Enum.any?(issues, fn issue -> issue.trigger == "zebra" end)
      assert Enum.any?(issues, fn issue -> issue.trigger == "banana" end)
    end)
  end

  test "it should NOT report issues with correct ascii sort method ordering" do
    """
    defmodule CredoSampleModule do
      @type Abc :: String.t()
      @type Zebra :: String.t()
      @type apple :: String.t()
      @type zebra :: String.t()
    end
    """
    |> to_source_file()
    |> run_check(TypespecOrder, sort_method: :ascii)
    |> refute_issues()
  end
end
