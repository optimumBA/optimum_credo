defmodule OptimumCredo.Check.Refactor.ToggleOnlyHandleEventTest do
  use Credo.Test.Case, async: true

  alias OptimumCredo.Check.Refactor.ToggleOnlyHandleEvent

  defp module(handlers, template) do
    ~s'''
    defmodule MyAppWeb.MenuLive do
      use MyAppWeb, :live_view

      def mount(_params, _session, socket), do: {:ok, assign(socket, :open, false)}

    #{handlers}

      def render(assigns) do
        ~H"""
        #{template}
        """
      end
    end
    '''
  end

  @template ~s|<div :if={@open}>menu</div>|

  test "reports toggle-only handlers whose key has a single :if consumer" do
    handlers = """
      def handle_event("toggle_menu", _params, socket) do
        {:noreply, assign(socket, :open, !socket.assigns.open)}
      end
    """

    handlers
    |> module(@template)
    |> to_source_file()
    |> run_check(ToggleOnlyHandleEvent)
    |> assert_issue(fn issue ->
      assert issue.line_no == 6
      assert issue.message =~ ":open"
    end)
  end

  test "recognises not, piped, bracket-access and update forms" do
    for body <- [
          "{:noreply, assign(socket, :open, not socket.assigns.open)}",
          "{:noreply, socket |> assign(:open, !socket.assigns[:open])}",
          "{:noreply, update(socket, :open, &(!&1))}",
          "{:noreply, update(socket, :open, &(not &1))}",
          "{:noreply, update(socket, :open, fn open -> not open end)}"
        ] do
      "  def handle_event(\"toggle_menu\", _params, socket), do: #{body}"
      |> module(@template)
      |> to_source_file()
      |> run_check(ToggleOnlyHandleEvent)
      |> assert_issue()
    end
  end

  test "recognises `<%= if @key do %>` as the single consumer" do
    "  def handle_event(\"toggle_menu\", _params, socket), do: {:noreply, update(socket, :open, &(!&1))}"
    |> module("<%= if @open do %>menu<% end %>")
    |> to_source_file()
    |> run_check(ToggleOnlyHandleEvent)
    |> assert_issue()
  end

  test "ignores handlers that do more than toggle" do
    for body <- [
          "{:noreply, assign(socket, :open, true)}",
          "{:noreply, socket |> assign(:open, !socket.assigns.open) |> assign(:other, 1)}",
          "{:noreply, assign(socket, :open, !socket.assigns.closed)}",
          "{:noreply, assign(socket, :other, !socket.assigns.open)}",
          "{:noreply, update(socket, :open, &(&1 + 1))}",
          "{:noreply, push_event(assign(socket, :open, !socket.assigns.open), \"x\", %{})}"
        ] do
      "  def handle_event(\"toggle_menu\", _params, socket), do: #{body}"
      |> module(@template)
      |> to_source_file()
      |> run_check(ToggleOnlyHandleEvent)
      |> refute_issues()
    end
  end

  test "ignores keys used more than once in the template or read by other code" do
    handler =
      "  def handle_event(\"toggle_menu\", _params, socket), do: {:noreply, update(socket, :open, &(!&1))}"

    handler
    |> module(~s|<div :if={@open}>menu</div><span class={@open && "x"}></span>|)
    |> to_source_file()
    |> run_check(ToggleOnlyHandleEvent)
    |> refute_issues()

    handler
    |> module(~s|<div class={@open}>menu</div>|)
    |> to_source_file()
    |> run_check(ToggleOnlyHandleEvent)
    |> refute_issues()

    (handler <>
       "\n  def handle_event(\"save\", _p, socket), do: {:noreply, if(socket.assigns.open, do: socket)}")
    |> module(@template)
    |> to_source_file()
    |> run_check(ToggleOnlyHandleEvent)
    |> refute_issues()
  end

  test "modules without inline templates are skipped unless require_inline_template is false" do
    source = """
    defmodule MyAppWeb.MenuLive do
      use MyAppWeb, :live_view
      def handle_event("toggle_menu", _params, socket), do: {:noreply, update(socket, :open, &(!&1))}
    end
    """

    source
    |> to_source_file()
    |> run_check(ToggleOnlyHandleEvent)
    |> refute_issues()

    source
    |> to_source_file()
    |> run_check(ToggleOnlyHandleEvent, require_inline_template: false)
    |> assert_issue()
  end

  test "ignores non-LiveView modules" do
    """
    defmodule MyApp.Thing do
      def handle_event("toggle_menu", _params, socket), do: {:noreply, update(socket, :open, &(!&1))}
      def render(assigns), do: ~H"<div :if={@open}>x</div>"
    end
    """
    |> to_source_file()
    |> run_check(ToggleOnlyHandleEvent)
    |> refute_issues()
  end

  test "a consumer or reference mentioned only in comments, script or text does not count" do
    handlers = """
      def handle_event("toggle_menu", _params, socket) do
        {:noreply, assign(socket, :open, !socket.assigns.open)}
      end
    """

    commented = ~s|<!-- <div :if={@open}>menu</div> -->|

    refute_issues(
      handlers
      |> module(commented)
      |> to_source_file()
      |> run_check(ToggleOnlyHandleEvent)
    )

    heex_commented = ~s|<%!-- <div :if={@open}>menu</div> --%>|

    refute_issues(
      handlers
      |> module(heex_commented)
      |> to_source_file()
      |> run_check(ToggleOnlyHandleEvent)
    )

    text_only = ~s|<p>write :if={@open} to hide</p>|

    refute_issues(
      handlers
      |> module(text_only)
      |> to_source_file()
      |> run_check(ToggleOnlyHandleEvent)
    )

    # A commented duplicate must not make a real single consumer look like two.
    both = ~s|<%!-- <span :if={@open}>old</span> --%><div :if={@open}>menu</div>|

    assert [_item] =
             handlers
             |> module(both)
             |> to_source_file()
             |> run_check(ToggleOnlyHandleEvent)
  end

  test "a template in another module of the same file does not count" do
    """
    defmodule MyAppWeb.MenuLive do
      use MyAppWeb, :live_view

      def handle_event("toggle_menu", _params, socket) do
        {:noreply, assign(socket, :open, !socket.assigns.open)}
      end

      def render(assigns), do: ~H"<p>no consumer</p>"
    end

    defmodule MyAppWeb.OtherLive do
      use MyAppWeb, :live_view

      def render(assigns), do: ~H"<div :if={@open}>menu</div>"
    end
    """
    |> to_source_file()
    |> run_check(ToggleOnlyHandleEvent)
    |> refute_issues()
  end

  test "a nested module is judged on its own template" do
    """
    defmodule MyAppWeb.MenuLive do
      use MyAppWeb, :live_view

      def handle_event("toggle_menu", _params, socket) do
        {:noreply, assign(socket, :open, !socket.assigns.open)}
      end

      def render(assigns), do: ~H"<div :if={@open}>menu</div>"

      defmodule Inner do
        use MyAppWeb, :live_view

        def render(assigns), do: ~H"<div :if={@open}>again</div>"
      end
    end
    """
    |> to_source_file()
    |> run_check(ToggleOnlyHandleEvent)
    |> assert_issue(fn issue -> assert issue.line_no == 4 end)
  end

  test "the handler must update and read its own socket" do
    handlers = """
      def handle_event("toggle_menu", _params, socket) do
        {:noreply, assign(other_socket(), :open, !socket.assigns.open)}
      end
    """

    refute_issues(
      handlers
      |> module(@template)
      |> to_source_file()
      |> run_check(ToggleOnlyHandleEvent)
    )
  end
end
