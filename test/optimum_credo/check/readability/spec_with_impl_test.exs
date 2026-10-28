defmodule OptimumCredo.Check.Readability.SpecWithImplTest do
  use Credo.Test.Case, async: true

  alias OptimumCredo.Check.Readability.SpecWithImpl

  test "reports @spec after @impl with a module and with true" do
    """
    defmodule Demo do
      @impl Phoenix.LiveView
      @spec mount(map(), map(), term()) :: {:ok, term()}
      def mount(_params, _session, socket), do: {:ok, socket}

      @impl true
      @spec init(term()) :: {:ok, term()}
      def init(arg), do: {:ok, arg}
    end
    """
    |> to_source_file()
    |> run_check(SpecWithImpl)
    |> assert_issues(fn issues ->
      assert issues
             |> Enum.map(& &1.line_no)
             |> Enum.sort() == [3, 7]

      assert Enum.all?(issues, &(&1.message =~ "Remove @spec"))
    end)
  end

  test "reports @spec before @impl, with guards and on multi-clause functions" do
    """
    defmodule Demo do
      @spec handle_event(String.t(), map(), term()) :: {:noreply, term()} when term: var
      @impl Phoenix.LiveView
      def handle_event("a", _params, socket), do: {:noreply, socket}
      def handle_event("b", _params, socket), do: {:noreply, socket}
    end
    """
    |> to_source_file()
    |> run_check(SpecWithImpl)
    |> assert_issue(fn issue -> assert issue.line_no == 2 end)
  end

  test "ignores public functions with a spec and no impl, and @impl false" do
    """
    defmodule Demo do
      @spec run(term()) :: :ok
      def run(_arg), do: :ok

      @impl false
      @spec helper() :: :ok
      def helper, do: :ok
    end
    """
    |> to_source_file()
    |> run_check(SpecWithImpl)
    |> refute_issues()
  end

  test "does not leak @impl to the next function or to specs of other functions" do
    """
    defmodule Demo do
      @impl true
      def init(arg), do: {:ok, arg}

      @spec run(term()) :: :ok
      def run(_arg), do: :ok

      @impl true
      @spec other() :: :ok
      def handle_info(_msg, state), do: {:noreply, state}
    end
    """
    |> to_source_file()
    |> run_check(SpecWithImpl)
    |> refute_issues()
  end

  test "handles nested modules and defimpl bodies independently" do
    """
    defmodule Demo do
      defmodule Inner do
        @impl true
        @spec init(term()) :: {:ok, term()}
        def init(arg), do: {:ok, arg}
      end

      defimpl String.Chars, for: Inner do
        @impl true
        @spec to_string(Inner.t()) :: String.t()
        def to_string(_inner), do: "inner"
      end

      @spec init(term()) :: :ok
      def init(_arg), do: :ok
    end
    """
    |> to_source_file()
    |> run_check(SpecWithImpl)
    |> assert_issues(fn issues ->
      assert issues
             |> Enum.map(& &1.line_no)
             |> Enum.sort() == [4, 10]
    end)
  end

  test "ignores strings and quoted text mentioning @impl and @spec" do
    ~S'''
    defmodule Demo do
      @moduledoc "Write @impl true then @spec foo() :: :ok"
      def run, do: "@impl true @spec run() :: :ok"
    end
    '''
    |> to_source_file()
    |> run_check(SpecWithImpl)
    |> refute_issues()
  end

  test "matches specs to the callback by arity" do
    """
    defmodule Demo do
      @impl true
      @spec handle_event(String.t(), map()) :: :ok
      @spec handle_event(String.t(), map(), term()) :: {:noreply, term()}
      def handle_event(event, params, socket), do: {:noreply, {event, params, socket}}
    end
    """
    |> to_source_file()
    |> run_check(SpecWithImpl)
    |> assert_issue(fn issue -> assert issue.line_no == 4 end)
  end

  test "default arguments cover lower arities" do
    """
    defmodule Demo do
      @impl true
      @spec render(map()) :: String.t()
      def render(assigns, opts \\\\ []), do: {assigns, opts}
    end
    """
    |> to_source_file()
    |> run_check(SpecWithImpl)
    |> assert_issue(fn issue -> assert issue.line_no == 3 end)
  end

  test "handles parenless zero-arity callbacks, when guards and spec constraints" do
    """
    defmodule Demo do
      @impl true
      @spec child_spec :: map()
      def child_spec, do: %{}

      @impl GenServer
      @spec handle_info(term(), state) :: {:noreply, state} when state: term()
      def handle_info(msg, state) when is_atom(msg), do: {:noreply, state}
    end
    """
    |> to_source_file()
    |> run_check(SpecWithImpl)
    |> assert_issue(fn issue -> assert issue.line_no == 7 end)
  end

  test "accepts @spec on a private helper that follows a callback" do
    """
    defmodule Demo do
      @impl true
      def init(arg), do: {:ok, helper(arg)}

      @spec helper(term()) :: term()
      defp helper(arg), do: arg
    end
    """
    |> to_source_file()
    |> run_check(SpecWithImpl)
    |> refute_issues()
  end
end
