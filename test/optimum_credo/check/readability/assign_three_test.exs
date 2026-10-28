defmodule OptimumCredo.Check.Readability.AssignThreeTest do
  use Credo.Test.Case, async: true

  alias OptimumCredo.Check.Readability.AssignThree

  test "reports keyword and map literals passed to assign/2" do
    """
    defmodule MyAppWeb.PostLive do
      def mount(_params, _session, socket) do
        socket = assign(socket, page: 1, per_page: 20)
        {:ok, assign(socket, %{title: "Posts"})}
      end
    end
    """
    |> to_source_file()
    |> run_check(AssignThree)
    |> assert_issues(fn issues -> assert Enum.map(issues, & &1.line_no) == [3, 4] end)
  end

  test "reports the piped and remote forms" do
    """
    defmodule MyAppWeb.PostLive do
      def a(socket), do: socket |> assign(page: 1)
      def b(socket), do: Phoenix.Component.assign(socket, page: 1)
    end
    """
    |> to_source_file()
    |> run_check(AssignThree)
    |> assert_issues(fn issues -> assert length(issues) == 2 end)
  end

  test "allows assign/3, variable forwarding and empty literals" do
    """
    defmodule MyAppWeb.PostLive do
      def update(assigns, socket) do
        socket
        |> assign(:page, 1)
        |> assign(assigns)
        |> assign(socket, assigns)
        |> assign(socket, [])
        |> assign(Map.take(assigns, [:id]))
        |> then(&{:ok, &1})
      end
    end
    """
    |> to_source_file()
    |> run_check(AssignThree)
    |> refute_issues()
  end

  test "ignores literals in strings, comments and quoted code that is not a call" do
    ~S'''
    defmodule MyAppWeb.PostLive do
      # assign(socket, a: 1)
      @doc "assign(socket, a: 1)"
      def hint, do: "assign(socket, page: 1)"
      def other, do: assign_all(socket, page: 1)
    end
    '''
    |> to_source_file()
    |> run_check(AssignThree)
    |> refute_issues()
  end

  test "does not inspect standalone heex files" do
    source_file = Credo.SourceFile.parse("<div></div>", "lib/a.html.heex")

    assert [] = run_check(source_file, AssignThree)
  end

  test "does not report function heads, patterns or typespecs that look like calls" do
    """
    defmodule MyAppWeb.Helpers do
      @callback assign(term, a: integer) :: term
      @spec assign(term, [name: String.t()]) :: term
      def assign(socket, a: 1), do: socket
      defp assign(socket, %{a: 1}), do: socket
      defmacro assign(socket, b: 2), do: socket
    end
    """
    |> to_source_file()
    |> run_check(AssignThree)
    |> refute_issues()
  end

  test "reports a literal in a nested module and inside quote, with the call's line" do
    """
    defmodule Outer do
      defmodule Inner do
        def run(socket) do
          socket
          |> assign(page: 1)
        end
      end

      def other(socket), do: quote(do: assign(socket, %{a: 1}))
    end
    """
    |> to_source_file()
    |> run_check(AssignThree)
    |> assert_issues(fn issues -> assert Enum.map(issues, & &1.line_no) == [5, 9] end)
  end
end
