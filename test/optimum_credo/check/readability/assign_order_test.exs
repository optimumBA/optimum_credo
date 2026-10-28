defmodule OptimumCredo.Check.Readability.AssignOrderTest do
  use Credo.Test.Case, async: true

  alias OptimumCredo.Check.Readability.AssignOrder

  test "reports an unsorted pipeline chain at the first out-of-order stage" do
    """
    defmodule Live do
      def mount(socket) do
        socket
        |> assign(:title, "Hi")
        |> assign(:count, 0)
        |> assign(:user, nil)
      end
    end
    """
    |> to_source_file()
    |> run_check(AssignOrder)
    |> assert_issue(fn issue ->
      assert issue.line_no == 5
      assert issue.message =~ "count"
    end)
  end

  test "reports keyword and map literals" do
    """
    defmodule Live do
      def a(socket), do: assign(socket, title: "Hi", count: 0, user: nil)
      def b(socket), do: assign(socket, %{title: "Hi", count: 0, user: nil})
      def c(socket), do: socket |> assign(title: "Hi", count: 0) |> assign(:user, nil)
    end
    """
    |> to_source_file()
    |> run_check(AssignOrder)
    |> assert_issues(fn issues -> assert Enum.map(issues, & &1.line_no) == [2, 3, 4] end)
  end

  test "accepts sorted chains and pinned module first" do
    """
    defmodule Live do
      def mount(socket) do
        socket
        |> assign(:module, __MODULE__)
        |> assign(:count, 0)
        |> assign(:title, "Hi")
      end
    end
    """
    |> to_source_file()
    |> run_check(AssignOrder)
    |> refute_issues()
  end

  test "reports a pinned key that is not first, and honors custom pins" do
    source = """
    defmodule Live do
      def mount(socket) do
        socket
        |> assign(:count, 0)
        |> assign(:module, __MODULE__)
        |> assign(:title, "Hi")
      end
    end
    """

    source
    |> to_source_file()
    |> run_check(AssignOrder)
    |> assert_issue()

    source
    |> to_source_file()
    |> run_check(AssignOrder, pinned_assigns: [])
    |> refute_issues()
  end

  test "other stages and dynamic keys end the chain" do
    """
    defmodule Live do
      def mount(socket, key) do
        socket
        |> assign(:title, "Hi")
        |> assign(:count, 0)
        |> maybe_load()
        |> assign(:alpha, 1)
        |> assign(key, 2)
        |> assign(:aaa, 3)
        |> assign(socket.assigns)
        |> assign(:zzz, 4)
      end
    end
    """
    |> to_source_file()
    |> run_check(AssignOrder, min_run: 2)
    |> assert_issue(fn issue -> assert issue.line_no == 5 end)
  end

  test "short chains, separate statements and variable maps are ignored" do
    """
    defmodule Live do
      def mount(socket, assigns) do
        socket = assign(socket, :title, "Hi")
        socket = assign(socket, :count, 0)
        socket = assign(socket, :user, nil)
        socket |> assign(:b, 1) |> assign(:a, 2)
        assign(socket, assigns)
      end
    end
    """
    |> to_source_file()
    |> run_check(AssignOrder)
    |> refute_issues()
  end

  test "min_run can include two-key chains" do
    "defmodule L do\n  def m(s), do: s |> assign(:b, 1) |> assign(:a, 2)\nend"
    |> to_source_file()
    |> run_check(AssignOrder, min_run: 2)
    |> assert_issue()
  end

  test "finds chains nested in other expressions and ignores strings" do
    ~S'''
    defmodule Live do
      def mount(socket) do
        {:ok,
         socket
         |> assign(:c, 1)
         |> assign(:b, 2)
         |> assign(:a, 3)}
      end

      def text, do: "socket |> assign(:c, 1) |> assign(:b, 2) |> assign(:a, 3)"
    end
    '''
    |> to_source_file()
    |> run_check(AssignOrder)
    |> assert_issue(fn issue -> assert issue.line_no == 6 end)
  end

  test "a realistic mount chain with a pinned module assign" do
    """
    defmodule MyAppWeb.PostLive do
      def mount(_params, _session, socket) do
        {:ok,
         socket
         |> assign(:module, __MODULE__)
         |> assign(:page_title, "Posts")
         |> assign(:posts, [])
         |> assign(:current_user, nil)}
      end
    end
    """
    |> to_source_file()
    |> run_check(AssignOrder)
    |> assert_issue(fn issue ->
      assert issue.line_no == 8
      assert issue.message =~ "current_user"
    end)
  end

  test "pinned assigns keep their configured order and strings are accepted" do
    source = """
    defmodule Demo do
      def a(socket) do
        socket
        |> assign(:page_title, "x")
        |> assign(:module, __MODULE__)
        |> assign(:posts, [])
      end
    end
    """

    source
    |> to_source_file()
    |> run_check(AssignOrder, pinned_assigns: ["module", "page_title"])
    |> assert_issue(fn issue -> assert issue.line_no == 5 end)

    source
    |> to_source_file()
    |> run_check(AssignOrder, pinned_assigns: [:page_title, :module])
    |> refute_issues()
  end

  test "keyword form respects pinned keys and ends on non-literal keys" do
    """
    defmodule Demo do
      def a(socket) do
        assign(socket, module: __MODULE__, posts: [], page_title: "x")
      end

      def b(socket, key) do
        socket
        |> assign(:z, 1)
        |> assign(key, 2)
        |> assign(:a, 3)
        |> assign(:b, 4)
      end
    end
    """
    |> to_source_file()
    |> run_check(AssignOrder)
    |> assert_issue(fn issue -> assert issue.line_no == 3 end)
  end

  test "separate pipelines in one function are separate chains" do
    """
    defmodule Demo do
      def a(socket) do
        one = socket |> assign(:b, 1) |> assign(:c, 2)
        two = socket |> assign(:a, 1) |> assign(:d, 2)
        {one, two}
      end
    end
    """
    |> to_source_file()
    |> run_check(AssignOrder, min_run: 2)
    |> refute_issues()
  end
end
