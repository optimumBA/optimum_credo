defmodule OptimumCredo.Check.Readability.ModuleAttributeListOrderTest do
  use Credo.Test.Case, async: true

  alias OptimumCredo.Check.Readability.ModuleAttributeListOrder

  test "reports unsorted atom, string, and ~w lists" do
    """
    defmodule Demo do
      @roles [:member, :admin, :guest]
      @kinds ["b", "a", "c"]
      @words ~w(beta alpha gamma)
      @atoms ~w(beta alpha gamma)a
    end
    """
    |> to_source_file()
    |> run_check(ModuleAttributeListOrder)
    |> assert_issues(fn issues ->
      assert Enum.map(issues, & &1.line_no) == [2, 3, 4, 5]
      assert hd(issues).message =~ "@roles"
    end)
  end

  test "accepts sorted, short, keyword, mixed and dynamic values" do
    """
    defmodule Demo do
      @roles [:admin, :guest, :member]
      @short [:b, :a]
      @opts [b: 1, a: 2, c: 3]
      @mixed [:b, "a", :c]
      @dynamic Enum.sort([:c, :b, :a])
      @numbers [3, 2, 1]
      @words ~w(alpha beta gamma)
    end
    """
    |> to_source_file()
    |> run_check(ModuleAttributeListOrder)
    |> refute_issues()
  end

  test "does not inspect built-in attributes" do
    """
    defmodule Demo do
      @derive [Jason.Encoder, Inspect, Access]
      @dialyzer [:no_return, :no_match, :error_handling]
      @compile [:inline, :debug_info, :bin_opt_info]
    end
    """
    |> to_source_file()
    |> run_check(ModuleAttributeListOrder)
    |> refute_issues()
  end

  test "ignore_attributes (atoms or strings) and min_run parameters" do
    source = """
    defmodule Demo do
      @stages [:validate, :build, :deploy]
      @pair [:b, :a]
    end
    """

    source
    |> to_source_file()
    |> run_check(ModuleAttributeListOrder, ignore_attributes: [:stages])
    |> refute_issues()

    source
    |> to_source_file()
    |> run_check(ModuleAttributeListOrder, ignore_attributes: ["stages"], min_run: 2)
    |> assert_issue(fn issue -> assert issue.message =~ "@pair" end)
  end

  test "ignores attribute reads and text containing lists" do
    ~S'''
    defmodule Demo do
      @moduledoc "Use @roles [:c, :b, :a]"
      def roles, do: @roles
      def text, do: "@roles [:c, :b, :a]"
    end
    '''
    |> to_source_file()
    |> run_check(ModuleAttributeListOrder)
    |> refute_issues()
  end

  test "checks ~w sigils with atom modifier and skips interpolated or other-modifier sigils" do
    """
    defmodule Demo do
      @roles ~w(user admin guest)a
      @names ~w(b a c)s
      @charlist ~w(b a c)c
      @dynamic ~w(b a \#{1})
    end
    """
    |> to_source_file()
    |> run_check(ModuleAttributeListOrder)
    |> assert_issues(fn issues ->
      assert Enum.map(issues, & &1.line_no) == [2, 3, 4]
    end)
  end

  test "semantic order is protected by ignore_attributes while neighbors are still checked" do
    """
    defmodule Demo do
      @stages [:validate, :authorize, :execute]
      @allowed_fields [:name, :email, :age]
    end
    """
    |> to_source_file()
    |> run_check(ModuleAttributeListOrder, ignore_attributes: [:stages])
    |> assert_issue(fn issue ->
      assert issue.line_no == 3
      assert issue.message =~ "@allowed_fields"
    end)
  end

  test "attributes inside nested modules and multi-line lists report the attribute line" do
    """
    defmodule Outer do
      defmodule Inner do
        @fields [
          :name,
          :email,
          :age
        ]
      end
    end
    """
    |> to_source_file()
    |> run_check(ModuleAttributeListOrder)
    |> assert_issue(fn issue -> assert issue.line_no == 3 end)
  end
end
