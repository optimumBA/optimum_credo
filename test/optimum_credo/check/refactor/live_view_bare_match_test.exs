defmodule OptimumCredo.Check.Refactor.LiveViewBareMatchTest do
  use Credo.Test.Case, async: true

  alias OptimumCredo.Check.Refactor.LiveViewBareMatch

  test "it should NOT report bare matches in non-LiveView modules" do
    """
    defmodule MyApp.Posts do
      def create(attrs) do
        {:ok, post} = Repo.insert(%Post{})
        post
      end
    end
    """
    |> to_source_file()
    |> run_check(LiveViewBareMatch)
    |> refute_issues()
  end

  test "it should report bare {:ok, _} = match in a Phoenix.LiveView module" do
    """
    defmodule MyAppWeb.PostLive do
      use Phoenix.LiveView

      def handle_event("create", params, socket) do
        {:ok, post} = Posts.create_post(params)
        {:noreply, socket}
      end
    end
    """
    |> to_source_file()
    |> run_check(LiveViewBareMatch)
    |> assert_issue(fn issue ->
      assert issue.message =~ "Bare `{:ok, _} =` match in LiveView"
    end)
  end

  test "it should report bare {:error, _} = match in a Phoenix.LiveView module" do
    """
    defmodule MyAppWeb.PostLive do
      use Phoenix.LiveView

      def handle_event("delete", %{"id" => id}, socket) do
        {:error, changeset} = Posts.delete_post(id)
        {:noreply, socket}
      end
    end
    """
    |> to_source_file()
    |> run_check(LiveViewBareMatch)
    |> assert_issue(fn issue ->
      assert issue.message =~ "Bare `{:error, _} =` match in LiveView"
    end)
  end

  test "it should report bare match with `use AppWeb, :live_view` pattern" do
    """
    defmodule MyAppWeb.PostLive do
      use MyAppWeb, :live_view

      def handle_event("create", params, socket) do
        {:ok, post} = Posts.create_post(params)
        {:noreply, socket}
      end
    end
    """
    |> to_source_file()
    |> run_check(LiveViewBareMatch)
    |> assert_issue(fn issue ->
      assert issue.message =~ "Bare `{:ok, _} =` match in LiveView"
    end)
  end

  test "it should report bare match in Phoenix.LiveComponent module" do
    """
    defmodule MyAppWeb.PostComponent do
      use Phoenix.LiveComponent

      def handle_event("save", params, socket) do
        {:ok, _post} = Posts.update_post(params)
        {:noreply, socket}
      end
    end
    """
    |> to_source_file()
    |> run_check(LiveViewBareMatch)
    |> assert_issue(fn issue ->
      assert issue.message =~ "Bare `{:ok, _} =` match in LiveView"
    end)
  end

  test "it should report bare match with `use AppWeb, :live_component` pattern" do
    """
    defmodule MyAppWeb.PostComponent do
      use MyAppWeb, :live_component

      def handle_event("save", params, socket) do
        {:ok, _post} = Posts.update_post(params)
        {:noreply, socket}
      end
    end
    """
    |> to_source_file()
    |> run_check(LiveViewBareMatch)
    |> assert_issue(fn issue ->
      assert issue.message =~ "Bare `{:ok, _} =` match in LiveView"
    end)
  end

  test "it should NOT report case expressions in LiveView" do
    """
    defmodule MyAppWeb.PostLive do
      use Phoenix.LiveView

      def handle_event("create", params, socket) do
        case Posts.create_post(params) do
          {:ok, _post} -> {:noreply, put_flash(socket, :info, "Created!")}
          {:error, changeset} -> {:noreply, assign(socket, :changeset, changeset)}
        end
      end
    end
    """
    |> to_source_file()
    |> run_check(LiveViewBareMatch)
    |> refute_issues()
  end

  test "it should NOT report with in LiveView" do
    """
    defmodule MyAppWeb.PostLive do
      use Phoenix.LiveView

      def handle_event("create", params, socket) do
        with {:ok, post} <- Posts.create_post(params),
             {:ok, _} <- Notifications.send(post) do
          {:noreply, put_flash(socket, :info, "Done")}
        else
          {:error, changeset} -> {:noreply, assign(socket, :changeset, changeset)}
        end
      end
    end
    """
    |> to_source_file()
    |> run_check(LiveViewBareMatch)
    |> refute_issues()
  end

  test "it should report multiple bare matches in the same module" do
    """
    defmodule MyAppWeb.PostLive do
      use Phoenix.LiveView

      def handle_event("create", params, socket) do
        {:ok, post} = Posts.create_post(params)
        {:ok, _log} = Audit.log(:create, post)
        {:noreply, socket}
      end
    end
    """
    |> to_source_file()
    |> run_check(LiveViewBareMatch)
    |> assert_issues(fn issues ->
      assert length(issues) == 2
    end)
  end

  test "it should report the correct line number" do
    """
    defmodule MyAppWeb.PostLive do
      use Phoenix.LiveView

      def handle_event("create", params, socket) do
        {:ok, post} = Posts.create_post(params)
        {:noreply, socket}
      end
    end
    """
    |> to_source_file()
    |> run_check(LiveViewBareMatch)
    |> assert_issue(fn issue ->
      assert issue.line_no == 5
    end)
  end

  test "it should NOT report ok tuple used as return value (not a match)" do
    """
    defmodule MyAppWeb.PostLive do
      use Phoenix.LiveView

      def mount(_params, _session, socket) do
        {:ok, assign(socket, :posts, [])}
      end
    end
    """
    |> to_source_file()
    |> run_check(LiveViewBareMatch)
    |> refute_issues()
  end

  test "it should report bare match in handle_info callback" do
    """
    defmodule MyAppWeb.PostLive do
      use Phoenix.LiveView

      @impl Phoenix.LiveView
      def handle_info({:update, params}, socket) do
        {:ok, post} = Posts.update_post(params)
        {:noreply, socket}
      end
    end
    """
    |> to_source_file()
    |> run_check(LiveViewBareMatch)
    |> assert_issue(fn issue ->
      assert issue.message =~ "Bare `{:ok, _} =` match in LiveView"
    end)
  end

  test "it should use case suggestion in message" do
    """
    defmodule MyAppWeb.PostLive do
      use Phoenix.LiveView

      def handle_event("create", params, socket) do
        {:ok, post} = Posts.create_post(params)
        {:noreply, socket}
      end
    end
    """
    |> to_source_file()
    |> run_check(LiveViewBareMatch)
    |> assert_issue(fn issue ->
      assert issue.message =~ "use `case`"
    end)
  end
end
