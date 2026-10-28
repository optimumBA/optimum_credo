defmodule OptimumCredo.Check.Readability.DefaultCallbackDefinedTest do
  use Credo.Test.Case, async: true

  alias OptimumCredo.Check.Readability.DefaultCallbackDefined

  test "reports a default mount/3 in a LiveView" do
    """
    defmodule MyAppWeb.PostLive do
      use MyAppWeb, :live_view

      @impl true
      def mount(_params, _session, socket), do: {:ok, socket}
    end
    """
    |> to_source_file()
    |> run_check(DefaultCallbackDefined)
    |> assert_issue(fn issue ->
      assert issue.line_no == 5
      assert issue.message =~ "mount/3"
    end)
  end

  test "reports do-block mount, mount/1 and update/2 defaults in components" do
    """
    defmodule MyAppWeb.FormComponent do
      use Phoenix.LiveComponent

      def mount(socket) do
        {:ok, socket}
      end

      def update(assigns, socket) do
        {:ok, assign(socket, assigns)}
      end
    end
    """
    |> to_source_file()
    |> run_check(DefaultCallbackDefined)
    |> assert_issues(fn issues -> assert length(issues) == 2 end)
  end

  test "reports with Phoenix.LiveView and underscored session" do
    """
    defmodule MyAppWeb.PostLive do
      use Phoenix.LiveView
      def mount(_p, _s, sock), do: {:ok, sock}
    end
    """
    |> to_source_file()
    |> run_check(DefaultCallbackDefined)
    |> assert_issue()
  end

  test "ignores non-default callbacks" do
    """
    defmodule MyAppWeb.PostLive do
      use MyAppWeb, :live_view

      def mount(%{"id" => id}, _session, socket), do: {:ok, assign(socket, :id, id)}
    end

    defmodule MyAppWeb.Other do
      use MyAppWeb, :live_view
      def mount(_params, session, socket), do: {:ok, socket}
    end

    defmodule MyAppWeb.Third do
      use MyAppWeb, :live_view
      def mount(_params, _session, socket) when is_map(socket), do: {:ok, socket}
    end

    defmodule MyAppWeb.Fourth do
      use MyAppWeb, :live_view
      def mount(_params, _session, socket), do: {:ok, socket, layout: false}
    end

    defmodule MyAppWeb.Fifth do
      use MyAppWeb, :live_view
      def mount(_params, _session, socket), do: {:ok, other}
    end
    """
    |> to_source_file()
    |> run_check(DefaultCallbackDefined)
    |> refute_issues()
  end

  test "ignores multi-clause callbacks and components' update with extra work" do
    """
    defmodule MyAppWeb.PostLive do
      use MyAppWeb, :live_view

      def mount(%{"id" => _}, _session, socket), do: {:ok, socket}
      def mount(_params, _session, socket), do: {:ok, socket}
    end

    defmodule MyAppWeb.FormComponent do
      use MyAppWeb, :live_component
      def update(assigns, socket), do: {:ok, socket |> assign(assigns) |> assign(:a, 1)}
    end
    """
    |> to_source_file()
    |> run_check(DefaultCallbackDefined)
    |> refute_issues()
  end

  test "ignores modules that are not LiveViews, including mount/3 on plain modules" do
    """
    defmodule MyApp.Thing do
      use GenServer

      def mount(_params, _session, socket), do: {:ok, socket}
    end

    defmodule MyAppWeb.Page do
      use MyAppWeb, :html
      def mount(_params, _session, socket), do: {:ok, socket}
    end
    """
    |> to_source_file()
    |> run_check(DefaultCallbackDefined)
    |> refute_issues()
  end

  test "mount/1 and update/2 are not defaults for plain LiveViews" do
    """
    defmodule MyAppWeb.PostLive do
      use MyAppWeb, :live_view
      def mount(socket), do: {:ok, socket}
      def update(assigns, socket), do: {:ok, assign(socket, assigns)}
    end
    """
    |> to_source_file()
    |> run_check(DefaultCallbackDefined)
    |> refute_issues()
  end

  test "classifies each nested module on its own" do
    """
    defmodule MyAppWeb.Outer do
      use Phoenix.LiveView

      def mount(_params, _session, socket), do: {:ok, socket}

      defmodule Component do
        use Phoenix.LiveComponent

        def mount(socket), do: {:ok, socket}
        def update(assigns, socket), do: {:ok, Phoenix.Component.assign(socket, assigns)}
      end

      defmodule Plain do
        def mount(_params, _session, socket), do: {:ok, socket}
      end
    end
    """
    |> to_source_file()
    |> run_check(DefaultCallbackDefined)
    |> assert_issues(fn issues -> assert Enum.map(issues, & &1.line_no) == [4, 9, 10] end)
  end

  test "mount/3 is not a LiveComponent callback and keeps its meaning with guards or patterns" do
    """
    defmodule MyAppWeb.Card do
      use Phoenix.LiveComponent

      def mount(_params, _session, socket), do: {:ok, socket}
    end

    defmodule MyAppWeb.GuardedLive do
      use Phoenix.LiveView

      def mount(_params, _session, socket) when is_map(socket), do: {:ok, socket}
    end

    defmodule MyAppWeb.PatternLive do
      use Phoenix.LiveView

      def mount(%{"id" => _}, _session, socket), do: {:ok, socket}
    end

    defmodule MyAppWeb.PrivateLive do
      use Phoenix.LiveView

      defp mount(_params, _session, socket), do: {:ok, socket}
    end
    """
    |> to_source_file()
    |> run_check(DefaultCallbackDefined)
    |> refute_issues()
  end
end
