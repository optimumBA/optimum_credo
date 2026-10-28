defmodule OptimumCredo.Check.Refactor.DuplicateHandleEventTest do
  use Credo.Test.Case, async: true

  alias OptimumCredo.Check.Refactor.DuplicateHandleEvent

  defp live_view(name, handler) do
    """
    defmodule #{name} do
      use MyAppWeb, :live_view

    #{handler}
    end
    """
  end

  @handler """
    def handle_event("select_tab", %{"tab" => tab}, socket) do
      socket = assign(socket, :tab, tab)
      {:noreply, push_patch(socket, to: ~p"/items?tab=\#{tab}")}
    end
  """

  test "reports identical clauses across LiveViews even with renamed variables" do
    renamed = """
      def handle_event("select_tab", %{"tab" => value}, sock) do
        sock = assign(sock, :tab, value)
        {:noreply, push_patch(sock, to: ~p"/items?tab=\#{value}")}
      end
    """

    a =
      "MyAppWeb.ALive"
      |> live_view(@handler)
      |> to_source_file("lib/a_live.ex")

    b =
      "MyAppWeb.BLive"
      |> live_view(renamed)
      |> to_source_file("lib/b_live.ex")

    [a, b]
    |> run_check(DuplicateHandleEvent)
    |> assert_issues(fn issues ->
      assert length(issues) == 2
      assert Enum.all?(issues, &(&1.message =~ "select_tab"))

      assert issues
             |> Enum.map(& &1.filename)
             |> Enum.sort() == ["lib/a_live.ex", "lib/b_live.ex"]
    end)
  end

  test "the event name may differ" do
    a =
      "MyAppWeb.ALive"
      |> live_view(@handler)
      |> to_source_file()

    b =
      "MyAppWeb.BLive"
      |> live_view(String.replace(@handler, "select_tab", "pick_tab"))
      |> to_source_file()

    assert [_first, _second] = run_check([a, b], DuplicateHandleEvent)
  end

  test "ignores differing bodies, trivial clauses and duplicates inside one module" do
    other = String.replace(@handler, ":tab", ":panel")

    a =
      "MyAppWeb.ALive"
      |> live_view(@handler)
      |> to_source_file()

    b =
      "MyAppWeb.BLive"
      |> live_view(other)
      |> to_source_file()

    [a, b]
    |> run_check(DuplicateHandleEvent)
    |> refute_issues()

    trivial = ~s|  def handle_event("noop", _params, socket), do: {:noreply, socket}|

    t1 =
      "MyAppWeb.CLive"
      |> live_view(trivial)
      |> to_source_file()

    t2 =
      "MyAppWeb.DLive"
      |> live_view(trivial)
      |> to_source_file()

    [t1, t2]
    |> run_check(DuplicateHandleEvent)
    |> refute_issues()

    same =
      live_view("MyAppWeb.ELive", @handler <> String.replace(@handler, "select_tab", "other_tab"))

    same
    |> to_source_file()
    |> run_check(DuplicateHandleEvent)
    |> refute_issues()
  end

  test "ignores modules that are not LiveViews and handle_info clauses" do
    plain = to_source_file("defmodule A do\n#{@handler}\nend")
    plain2 = to_source_file("defmodule B do\n#{@handler}\nend")

    [plain, plain2]
    |> run_check(DuplicateHandleEvent)
    |> refute_issues()

    info = String.replace(@handler, "handle_event", "handle_info")

    a =
      "MyAppWeb.AInfo"
      |> live_view(info)
      |> to_source_file()

    b =
      "MyAppWeb.BInfo"
      |> live_view(info)
      |> to_source_file()

    [a, b]
    |> run_check(DuplicateHandleEvent)
    |> refute_issues()
  end

  test "min_modules and min_nodes params" do
    a =
      "MyAppWeb.ALive"
      |> live_view(@handler)
      |> to_source_file()

    b =
      "MyAppWeb.BLive"
      |> live_view(@handler)
      |> to_source_file()

    [a, b]
    |> run_check(DuplicateHandleEvent, min_modules: 3)
    |> refute_issues()

    [a, b]
    |> run_check(DuplicateHandleEvent, min_nodes: 500)
    |> refute_issues()
  end

  test "identical text that calls a module-local helper is not a duplicate" do
    handler = """
      def handle_event("go", %{"id" => id}, socket) do
        thing = prepare(id)
        {:noreply, assign(socket, :thing, thing)}
      end

      defp prepare(id), do: {:placeholder, id}
    """

    a =
      "MyAppWeb.ALive"
      |> live_view(handler)
      |> to_source_file()

    b =
      "MyAppWeb.BLive"
      |> live_view(String.replace(handler, ":placeholder", ":other"))
      |> to_source_file()

    [a, b]
    |> run_check(DuplicateHandleEvent)
    |> refute_issues()
  end

  test "__MODULE__ and differing module attributes make identical text differ" do
    handler = """
      def handle_event("go", %{"id" => id}, socket) do
        socket = assign(socket, :target, __MODULE__)
        {:noreply, push_navigate(socket, to: "/items/" <> to_string(id))}
      end
    """

    a =
      "MyAppWeb.ALive"
      |> live_view(handler)
      |> to_source_file()

    b =
      "MyAppWeb.BLive"
      |> live_view(handler)
      |> to_source_file()

    [a, b]
    |> run_check(DuplicateHandleEvent)
    |> refute_issues()

    attribute_handler = """
      @limit 10
      def handle_event("more", _params, socket) do
        socket = assign(socket, :limit, @limit)
        {:noreply, push_event(socket, "more", %{limit: @limit})}
      end
    """

    c =
      "MyAppWeb.CLive"
      |> live_view(attribute_handler)
      |> to_source_file()

    d =
      "MyAppWeb.DLive"
      |> live_view(String.replace(attribute_handler, "10", "20"))
      |> to_source_file()

    [c, d]
    |> run_check(DuplicateHandleEvent)
    |> refute_issues()

    e =
      "MyAppWeb.ELive"
      |> live_view(attribute_handler)
      |> to_source_file()

    assert [_first, _second] = run_check([c, e], DuplicateHandleEvent)
  end

  test "two anonymous patterns are not the same variable twice" do
    one = """
      def handle_event("go", {_, _}, socket) do
        socket = assign(socket, :first, nil)
        {:noreply, push_event(socket, "go", %{})}
      end
    """

    two = String.replace(one, "{_, _}", "{pair, pair}")

    a =
      "MyAppWeb.ALive"
      |> live_view(one)
      |> to_source_file()

    b =
      "MyAppWeb.BLive"
      |> live_view(two)
      |> to_source_file()

    [a, b]
    |> run_check(DuplicateHandleEvent)
    |> refute_issues()
  end

  test "module-local aliases are expanded before comparing" do
    handler = fn alias_line ->
      """
        #{alias_line}
        def handle_event("go", _params, socket) do
          items = Repo.all(Item)
          {:noreply, assign(socket, :items, items)}
        end
      """
    end

    a =
      "MyAppWeb.ALive"
      |> live_view(handler.("alias MyApp.Repo\n  alias MyApp.Billing.Item"))
      |> to_source_file()

    b =
      "MyAppWeb.BLive"
      |> live_view(handler.("alias MyApp.Repo\n  alias MyApp.Shop.Item"))
      |> to_source_file()

    c =
      "MyAppWeb.CLive"
      |> live_view(handler.("alias MyApp.Repo\n  alias MyApp.Billing.Item"))
      |> to_source_file()

    [a, b]
    |> run_check(DuplicateHandleEvent)
    |> refute_issues()

    assert [_first, _second] = run_check([a, c], DuplicateHandleEvent)
  end

  test "nested LiveViews are separate modules and defp handlers are ignored" do
    nested = """
    defmodule MyAppWeb.OuterLive do
      use MyAppWeb, :live_view

      defmodule InnerLive do
        use MyAppWeb, :live_view
    #{@handler}
      end
    end
    """

    b =
      "MyAppWeb.BLive"
      |> live_view(@handler)
      |> to_source_file()

    assert [_first, _second] = run_check([to_source_file(nested), b], DuplicateHandleEvent)

    private = String.replace(@handler, "def handle_event", "defp handle_event")

    c =
      "MyAppWeb.CLive"
      |> live_view(private)
      |> to_source_file()

    d =
      "MyAppWeb.DLive"
      |> live_view(private)
      |> to_source_file()

    [c, d]
    |> run_check(DuplicateHandleEvent)
    |> refute_issues()
  end

  test "raw .heex files are skipped without error" do
    heex = Credo.SourceFile.parse("<div phx-click=\"a\">x</div>", "lib/page.html.heex")

    a =
      "MyAppWeb.ALive"
      |> live_view(@handler)
      |> to_source_file()

    [heex, a]
    |> run_check(DuplicateHandleEvent)
    |> refute_issues()
  end
end
