defmodule OptimumCredo.Check.Readability.MaybePrefixTest do
  use Credo.Test.Case, async: true

  alias OptimumCredo.Check.Readability.MaybePrefix

  defp run(source, params \\ []) do
    source
    |> to_source_file()
    |> run_check(MaybePrefix, params)
  end

  test "reports multi-clause pass-through functions" do
    """
    defmodule Demo do
      defp load_user(socket, nil), do: socket
      defp load_user(socket, id), do: assign(socket, :user, Accounts.get_user(id))
    end
    """
    |> run()
    |> assert_issue(fn issue ->
      assert issue.line_no == 2
      assert issue.message =~ "maybe_load_user"
    end)
  end

  test "reports if, unless, case and cond branches returning the first argument" do
    """
    defmodule Demo do
      def a(socket, flag) do
        if flag, do: Notifier.send(socket), else: socket
      end

      def b(socket, flag) do
        unless flag do
          socket
        else
          socket |> Notifier.send()
        end
      end

      def c(socket, kind) do
        case kind do
          :skip -> socket
          _other -> Notifier.send(socket)
        end
      end

      def d(query, filter) do
        cond do
          is_nil(filter) -> query
          true -> where(query, filter)
        end
      end
    end
    """
    |> run()
    |> assert_issues(fn issues -> assert Enum.map(issues, & &1.line_no) == [2, 6, 14, 21] end)
  end

  test "accepts maybe_ names, predicates, allowed prefixes and callbacks" do
    """
    defmodule Demo do
      defp maybe_load(socket, nil), do: socket
      defp maybe_load(socket, id), do: assign(socket, :user, get(id))

      def ready?(socket, nil), do: socket
      def ready?(socket, id), do: get(socket, id)

      def ensure_user(socket, nil), do: socket
      def ensure_user(socket, id), do: get(socket, id)

      @impl true
      def handle_params(socket, nil), do: socket
      def handle_params(socket, id), do: get(socket, id)
    end
    """
    |> run(allowed_prefixes: ["ensure_"])
    |> refute_issues()
  end

  test "does not report always-transforming, never-passing or non-variable first-argument functions" do
    """
    defmodule Demo do
      def always(socket, id), do: assign(socket, :id, id)
      def never(socket, nil), do: raise("nil")
      def never(socket, id), do: get(socket, id)
      def literal(_socket, nil), do: :ok
      def literal(_socket, id), do: get(id)
      def literal_first(1, x), do: x
      def literal_first(n, x), do: add(n, x)
      def other_variable(socket, other), do: if(other, do: socket, else: other)
      def only_vars(a, b), do: if(a, do: a, else: b)
    end
    """
    |> run()
    |> refute_issues()
  end

  test "uses the first parameter even when pattern matched" do
    """
    defmodule Demo do
      def touch(%{} = socket, nil), do: socket
      def touch(%{} = socket, id), do: Store.put(socket, id)
    end
    """
    |> run()
    |> assert_issue()
  end

  test "prefix, allowed_prefixes and ignore_functions parameters" do
    source = """
    defmodule Demo do
      def load(socket, nil), do: socket
      def load(socket, id), do: get(socket, id)
    end
    """

    source
    |> run(prefix: "try_")
    |> assert_issue(fn issue -> assert issue.message =~ "try_load" end)

    source
    |> run(ignore_functions: [:load])
    |> refute_issues()

    source
    |> run(ignore_functions: ["load"])
    |> refute_issues()
  end

  test "ignores strings, macros and quoted code" do
    ~S'''
    defmodule Demo do
      def text, do: "def load(socket, nil), do: socket"
      defmacro load(socket, nil), do: socket
      defmacro load(socket, id), do: get(socket, id)
    end
    '''
    |> run()
    |> refute_issues()
  end

  test "same-named functions of different arity are judged separately" do
    """
    defmodule Demo do
      defp load(socket, nil), do: socket
      defp load(socket, id), do: assign(socket, :user, id)
      defp load(socket), do: socket
    end
    """
    |> to_source_file()
    |> run_check(MaybePrefix)
    |> assert_issue(fn issue -> assert issue.line_no == 2 end)

    """
    defmodule Demo do
      defp load(socket, nil), do: socket
      defp load(socket), do: assign(socket, :user, 1)
    end
    """
    |> to_source_file()
    |> run_check(MaybePrefix)
    |> refute_issues()
  end

  test "recursion over the first argument is not a conditional action" do
    """
    defmodule Demo do
      defp walk(acc, []), do: acc
      defp walk(acc, [head | tail]), do: walk(acc + head, tail)
    end
    """
    |> to_source_file()
    |> run_check(MaybePrefix)
    |> refute_issues()
  end

  test "clauses with rescue blocks are not analysed" do
    """
    defmodule Demo do
      defp fetch(socket, nil), do: socket

      defp fetch(socket, id) do
        assign(socket, :user, id)
      rescue
        _ -> socket
      end
    end
    """
    |> to_source_file()
    |> run_check(MaybePrefix)
    |> refute_issues()
  end

  test "an arity-specific @impl does not hide a same-named helper" do
    """
    defmodule Demo do
      @impl true
      def handle_event(event, params, socket), do: {event, params, socket}

      defp handle_event(socket, nil), do: socket
      defp handle_event(socket, id), do: assign(socket, :id, id)
    end
    """
    |> to_source_file()
    |> run_check(MaybePrefix)
    |> assert_issue(fn issue -> assert issue.line_no == 5 end)
  end

  test "function plugs with a (conn, opts) signature are not reported" do
    """
    defmodule DemoWeb.Auth do
      def call(conn, _opts) do
        case conn.path_info do
          ["health"] -> send_resp(conn, 200, "ok")
          _path -> conn
        end
      end

      def require_user(conn, opts) do
        if conn.assigns[:user], do: conn, else: halt(redirect(conn, to: opts[:to]))
      end

      defp store_return_to(%{params: %{"to" => to}} = conn, _opts), do: put_session(conn, :to, to)
      defp store_return_to(conn, _opts), do: conn
    end
    """
    |> run()
    |> refute_issues()
  end

  test "(conn, opts) names only exempt the plug signature" do
    """
    defmodule Demo do
      defp filter(conn, extra, opts) do
        if opts[:on], do: apply_it(conn, extra), else: conn
      end
    end
    """
    |> run()
    |> assert_issue()
  end

  test "a type-guarded pass-through clause is type dispatch, not a conditional action" do
    """
    defmodule Demo do
      defp to_integer(value) when is_binary(value), do: String.to_integer(value)
      defp to_integer(value) when is_integer(value), do: value
    end
    """
    |> run()
    |> refute_issues()
  end

  test "an unguarded or non-type-guarded pass-through is still reported" do
    """
    defmodule Demo do
      defp to_integer(value) when is_binary(value), do: String.to_integer(value)
      defp to_integer(value), do: value

      defp limit(query, size) when size > 0, do: apply_limit(query, size)
      defp limit(query, _size), do: query
    end
    """
    |> run()
    |> assert_issues(fn issues -> assert length(issues) == 2 end)
  end
end
