defmodule OptimumCredo.Check.Readability.EventNameSnakeCaseTest do
  use Credo.Test.Case, async: true

  alias OptimumCredo.Check.Readability.EventNameSnakeCase

  test "reports dashed and camelCase handle_event and push_event names" do
    """
    defmodule MyAppWeb.PostLive do
      def handle_event("save-draft", _params, socket), do: {:noreply, socket}
      def handle_event("saveDraft", _params, socket) when is_map(socket), do: {:noreply, socket}
      def handle_event("save_draft", _params, socket), do: {:noreply, socket}

      def notify(socket) do
        socket |> push_event("scroll-top", %{})
        push_event(socket, "scrollTop", %{})
        push_event(socket, "scroll_top", %{})
      end
    end
    """
    |> to_source_file()
    |> run_check(EventNameSnakeCase)
    |> assert_issues(fn issues ->
      assert issues
             |> Enum.map(& &1.line_no)
             |> Enum.sort() == [2, 3, 7, 8]
    end)
  end

  test "reports phx attributes in ~H sigils with a correct line" do
    ~S'''
    defmodule MyAppWeb.PostLive do
      def render(assigns) do
        ~H"""
        <button phx-click="save-draft">Save</button>
        <button phx-click="save_draft">Save</button>
        <form phx-submit="Send">x</form>
        <button phx-click={JS.push("ok-name")}>x</button>
        <button phx-click="lv:clear-flash">x</button>
        <div phx-click-away="close_menu"></div>
        """
      end
    end
    '''
    |> to_source_file()
    |> run_check(EventNameSnakeCase)
    |> assert_issues(fn issues ->
      assert issues
             |> Enum.map(& &1.line_no)
             |> Enum.sort() == [4, 6]
    end)
  end

  test "reads standalone .heex files" do
    source_file =
      Credo.SourceFile.parse(
        "<div>\n  <a phx-click=\"go-now\">x</a>\n</div>\n",
        "lib/post.html.heex"
      )

    source_file
    |> run_check(EventNameSnakeCase)
    |> assert_issue(fn issue -> assert issue.line_no == 2 end)
  end

  test "allowed_events and check_heex params" do
    source = ~S'''
    defmodule MyAppWeb.PostLive do
      def handle_event("save-draft", _params, socket), do: {:noreply, socket}
      def handle_event("keep-me", _params, socket), do: {:noreply, socket}
      def render(assigns), do: ~H"<a phx-click='bad-name'>x</a><b phx-click=\"also-bad\">x</b>"
    end
    '''

    source
    |> to_source_file()
    |> run_check(EventNameSnakeCase, allowed_events: ["keep-me", "save-draft"], check_heex: false)
    |> refute_issues()

    source
    |> to_source_file()
    |> run_check(EventNameSnakeCase, allowed_events: ["keep-me", "save-draft"])
    |> assert_issues(fn issues ->
      assert Enum.any?(issues, &(&1.message =~ "also-bad"))
      assert Enum.any?(issues, &(&1.message =~ "bad-name"))
      assert length(issues) == 2
    end)
  end

  test "ignores dynamic names, strings, comments and unrelated functions" do
    ~S'''
    defmodule MyAppWeb.PostLive do
      # handle_event("a-b", ...)
      @doc "push_event(socket, \"a-b\", %{})"
      def handle_event(name, _params, socket), do: {:noreply, push_event(socket, name, %{})}
      def other(socket), do: log_event(socket, "a-b")
    end
    '''
    |> to_source_file()
    |> run_check(EventNameSnakeCase)
    |> refute_issues()
  end

  test "single-quoted attributes are read too" do
    ~S'''
    defmodule MyAppWeb.PostLive do
      def render(assigns), do: ~H"<a phx-click='bad-name'>x</a><b phx-click=\"also-bad\">x</b>"
    end
    '''
    |> to_source_file()
    |> run_check(EventNameSnakeCase, allowed_events: ["bad-name"])
    |> assert_issue(fn issue -> assert issue.message =~ "also-bad" end)
  end

  test "ignores attributes in HTML/HEEx comments and script or style bodies" do
    ~S'''
    defmodule MyAppWeb.PostLive do
      def render(assigns) do
        ~H"""
        <!-- <button phx-click="a-b">x</button> -->
        <%!-- <button phx-click="c-d">x</button> --%>
        <script>el.innerHTML = '<b phx-click="e-f">x</b>'</script>
        <p>docs: phx-click="g-h"</p>
        <button data-phx-click="i-j" phx-click="real-one">x</button>
        """
      end
    end
    '''
    |> to_source_file()
    |> run_check(EventNameSnakeCase)
    |> assert_issue(fn issue ->
      assert issue.message =~ "real-one"
      assert issue.line_no == 8
    end)
  end

  test "reads other event attributes and ignores comments in .heex files" do
    ~s|<!-- <a phx-click="no-one"> -->\n<div phx-viewport-top="load-more" phx-window-keydown="Esc-key"></div>\n|
    |> Credo.SourceFile.parse("lib/p.html.heex")
    |> run_check(EventNameSnakeCase)
    |> assert_issues(fn issues -> assert Enum.map(issues, & &1.line_no) == [2, 2] end)
  end

  test "reports a bound handle_event name, but only arity 3 and not other definitions" do
    """
    defmodule MyAppWeb.PostLive do
      def handle_event("save-draft" = event, _params, socket), do: {:noreply, assign(socket, :e, event)}
      def handle_event(event = "a-b", _params, socket), do: {:noreply, assign(socket, :e, event)}
      def handle_event("two-args", socket), do: socket
      def other("x-y", _p, socket), do: socket
      @callback push_event(term, String.t()) :: term
    end
    """
    |> to_source_file()
    |> run_check(EventNameSnakeCase)
    |> assert_issues(fn issues -> assert Enum.map(issues, & &1.line_no) == [2, 3] end)
  end
end
