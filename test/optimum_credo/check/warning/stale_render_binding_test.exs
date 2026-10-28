defmodule OptimumCredo.Check.Warning.StaleRenderBindingTest do
  use Credo.Test.Case, async: true

  alias OptimumCredo.Check.Warning.StaleRenderBinding

  @file_name "test/my_app_web/live/foo_live_test.exs"

  defp run(code, params \\ [], file \\ @file_name) do
    code
    |> to_source_file(file)
    |> run_check(StaleRenderBinding, params)
  end

  test "reports assertion on html captured before an interaction" do
    """
    defmodule FooLiveTest do
      use ExUnit.Case
      test "clicks", %{conn: conn} do
        {:ok, view, html} = live(conn, "/")
        view |> element("button") |> render_click()
        assert html =~ "clicked"
      end
    end
    """
    |> run()
    |> assert_issue(fn issue ->
      assert issue.line_no == 6
      assert issue.trigger == "html"
    end)
  end

  test "reports a render result bound earlier and an interaction bound to another name" do
    """
    defmodule FooLiveTest do
      use ExUnit.Case
      test "clicks" do
        html = render(view)
        other = render_submit(view)
        refute html =~ "gone"
        assert other =~ "ok"
      end
    end
    """
    |> run()
    |> assert_issue(fn issue -> assert issue.line_no == 6 end)
  end

  test "accepts assertion before the interaction" do
    """
    defmodule FooLiveTest do
      use ExUnit.Case
      test "a" do
        {:ok, view, html} = live(conn, "/")
        assert html =~ "hello"
        render_click(view)
      end
    end
    """
    |> run()
    |> refute_issues()
  end

  test "accepts rebinding after the interaction" do
    """
    defmodule FooLiveTest do
      use ExUnit.Case
      test "a" do
        {:ok, view, html} = live(conn, "/")
        html = view |> element("button") |> render_click()
        assert html =~ "clicked"
      end
    end
    """
    |> run()
    |> refute_issues()
  end

  test "ignores underscored and non-render bindings, strings and quoted code" do
    """
    defmodule FooLiveTest do
      use ExUnit.Case
      test "a" do
        {:ok, view, _html} = live(conn, "/")
        text = "html"
        render_click(view)
        assert text == "html"
        quote do
          assert html =~ "x"
        end
      end
    end
    """
    |> run()
    |> refute_issues()
  end

  test "interactions param is configurable and non-test files are ignored" do
    code = """
    defmodule FooLiveTest do
      use ExUnit.Case
      test "a" do
        html = render(view)
        custom_click(view)
        assert html =~ "x"
      end
    end
    """

    code
    |> run()
    |> refute_issues()

    code
    |> run(interactions: [:custom_click])
    |> assert_issue()

    code
    |> run([interactions: [:custom_click]], "lib/foo.ex")
    |> refute_issues()
  end

  test "{:ok, view} patterns do not track the view as html" do
    """
    defmodule FooLiveTest do
      use ExUnit.Case
      test "a", %{conn: conn} do
        {:ok, view} = live_isolated(conn, MyLive)
        view |> element("button") |> render_click()
        assert has_element?(view, "#done")
      end
    end
    """
    |> run()
    |> refute_issues()
  end

  test "variables bound inside the assertion shadow the stale binding" do
    """
    defmodule FooLiveTest do
      use ExUnit.Case
      test "a", %{conn: conn} do
        {:ok, view, html} = live(conn, "/")
        render_click(view, "go")
        assert Enum.all?(["a"], fn html -> html =~ "a" end)
        assert html = render(view)
        assert html =~ "fresh"
      end
    end
    """
    |> run()
    |> refute_issues()
  end

  test "comparing a stale snapshot with a fresher one is the point of the test" do
    """
    defmodule FooLiveTest do
      use ExUnit.Case
      test "a", %{conn: conn} do
        {:ok, view, before_html} = live(conn, "/")
        after_html = render_click(view, "go")
        assert before_html != after_html
      end
    end
    """
    |> run()
    |> refute_issues()
  end

  test "reports assertions nested in Enum.each when the statement runs no interaction" do
    """
    defmodule FooLiveTest do
      use ExUnit.Case
      test "a", %{conn: conn} do
        {:ok, view, html} = live(conn, "/")
        render_click(view, "go")
        Enum.each(["x"], fn word -> assert html =~ word end)
      end
    end
    """
    |> run()
    |> assert_issue(fn issue -> assert issue.line_no == 6 end)
  end

  test "send to self is not an interaction, send to the view is" do
    """
    defmodule FooLiveTest do
      use ExUnit.Case
      test "a", %{conn: conn} do
        {:ok, view, html} = live(conn, "/")
        send(self(), :ping)
        assert html =~ "still fresh"
      end
    end
    """
    |> run()
    |> refute_issues()

    """
    defmodule FooLiveTest do
      use ExUnit.Case
      test "a", %{conn: conn} do
        {:ok, view, html} = live(conn, "/")
        send(view.pid, :ping)
        assert html =~ "stale"
      end
    end
    """
    |> run()
    |> assert_issue()
  end

  test "remote calls on unrelated modules are not producers or interactions" do
    """
    defmodule FooLiveTest do
      use ExUnit.Case
      test "a" do
        html = MyApp.Template.render("x")
        MyApp.Widget.render_click(1)
        assert html =~ "x"
      end
    end
    """
    |> run()
    |> refute_issues()
  end

  test "qualified Phoenix.LiveViewTest calls are tracked" do
    """
    defmodule FooLiveTest do
      use ExUnit.Case
      alias Phoenix.LiveViewTest, as: LV
      test "a", %{conn: conn} do
        {:ok, view, html} = LV.live(conn, "/")
        LV.render_click(view, "go")
        assert html =~ "x"
      end
    end
    """
    |> run()
    |> assert_issue()
  end

  test "a binding assigned inside a nested fn body is local" do
    """
    defmodule FooLiveTest do
      use ExUnit.Case
      test "a", %{conn: conn} do
        {:ok, view, html} = live(conn, "/")
        render_click(view, "go")
        assert wait_until(view, fn ->
                 html = render(view)
                 html =~ "done"
               end)
      end
    end
    """
    |> run()
    |> refute_issues()
  end
end
