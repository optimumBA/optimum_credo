defmodule OptimumCredo.Check.Warning.CommentedOutCodeTest do
  use Credo.Test.Case, async: true

  alias OptimumCredo.Check.Warning.CommentedOutCode

  defp run(code, params \\ []) do
    code
    |> to_source_file()
    |> run_check(CommentedOutCode, params)
  end

  test "reports a run of commented-out calls once, at its first line" do
    """
    defmodule A do
      def a do
        # IO.inspect(socket.assigns)
        # Repo.delete_all(User)
        :ok
      end
    end
    """
    |> run()
    |> assert_issue(fn issue -> assert issue.line_no == 3 end)
  end

  test "reports commented-out definitions and children entries" do
    """
    defmodule A do
      # def old(x) do
      #   x + 1
      # end
      children = [
        # MyApp.Cache,
        # MyApp.Other,
        MyApp.Repo
      ]
    end
    """
    |> run()
    |> assert_issues(fn issues -> assert Enum.map(issues, & &1.line_no) == [2, 6] end)
  end

  test "single line counts only when it opens a block, or with min_lines 1" do
    code = """
    defmodule A do
      # if enabled? do
      # IO.inspect(x)
      def a, do: 1
    end
    """

    code
    |> run()
    |> assert_issue()

    """
    defmodule A do
      # Repo.get(User, id)
      def a, do: 1
    end
    """
    |> run()
    |> refute_issues()

    """
    defmodule A do
      # IO.inspect(x)
      def a, do: 1
    end
    """
    |> run()
    |> assert_issue()

    """
    defmodule A do
      # IO.inspect(x)
      def a, do: 1
    end
    """
    |> run(min_lines: 1)
    |> assert_issue()
  end

  test "ignores prose, bare words, pragmas, tags and doctest-like text" do
    """
    defmodule A do
      # done
      # this is fine
      #
      # credo:disable-for-next-line Credo.Check.Foo
      # sobelow_skip ["XSS"]
      # TODO: call Repo.get(User, 1) later
      # FIXME: remove(x)
      # iex> Foo.bar(1)
      # ...> Foo.baz(2)
      # Returns the user (or nil) when found, see list/1.
      # Use it wisely, then call back.
      def a, do: 1
    end
    """
    |> run()
    |> refute_issues()
  end

  test "ignores strings, heredoc docs and trailing comments" do
    ~S'''
    defmodule A do
      @moduledoc """
      # IO.inspect(x)
      # Repo.delete_all(User)
      """
      def a do
        "# IO.inspect(x)\n# Repo.all(User)"
        run(1) # Repo.delete_all(User)
        run(2) # IO.inspect(y)
      end
    end
    '''
    |> run()
    |> refute_issues()
  end

  test "ignore_prefixes param" do
    code = """
    defmodule A do
      # tmp = IO.inspect(x)
      # tmp = Repo.all(User)
      def a, do: 1
    end
    """

    code
    |> run()
    |> assert_issue()

    code
    |> run(ignore_prefixes: ["tmp ="])
    |> refute_issues()
  end

  test "commented-out pipelines with leading |> are code" do
    """
    defmodule A do
      def a(x) do
        x
        # |> Enum.map(&foo/1)
        # |> Enum.filter(&bar/1)
        |> Enum.sort()
      end
    end
    """
    |> run()
    |> assert_issue(fn issue -> assert issue.line_no == 4 end)
  end

  test "commented-out DSL lines without parentheses are code" do
    """
    defmodule A.Schema do
      schema "x" do
        # field :title, :string
        # field :body, :string
        field :id, :string
      end
    end
    """
    |> run()
    |> assert_issue(fn issue -> assert issue.line_no == 3 end)
  end

  test "blank # lines and differing # columns do not split a commented-out block" do
    """
    defmodule A do
      # def old(x) do
      #
      #   foo(x)
      #   bar(x)
      # end
      def a, do: 1
    end
    """
    |> run()
    |> assert_issue(fn issue -> assert issue.line_no == 2 end)

    """
    defmodule A do
      def a do
        # case x do
          # foo(1)
          # bar(2)
        # end
        :ok
      end
    end
    """
    |> run()
    |> assert_issue()
  end

  test "documentation examples introduced by prose are not flagged" do
    """
    defmodule A do
      # Example:
      #   Foo.bar(1)
      #   Foo.baz(2)
      #
      # e.g.
      # MyApp.run(1)
      # MyApp.run(2)
      def a, do: 1
    end
    """
    |> run()
    |> refute_issues()
  end

  test "prose built from bare words and atoms is not code" do
    """
    defmodule A do
      # use the cache
      # see the docs
      # returns :ok
      # or :error
      # get the thing
      # delete 5 items
      def a, do: 1
    end
    """
    |> run()
    |> refute_issues()
  end

  test "trailing end-of-line comments are not own-line runs" do
    """
    defmodule A do
      def a do
        foo(1) # bar(2)
        baz(3) # qux(4)
        :ok
      end
    end
    """
    |> run()
    |> refute_issues()
  end

  test "strings and heredocs that look like comments are ignored" do
    ~S'''
    defmodule A do
      @doc """
      # foo(1)
      # bar(2)
      """
      def a, do: "# baz(3)\n# qux(4)"
    end
    '''
    |> run()
    |> refute_issues()
  end

  test "a qualified module entry with a trailing comma is code even alone" do
    """
    children = [
      # MyApp.Cache,
      MyApp.Repo
    ]
    """
    |> run()
    |> assert_issue()
  end

  test "commented-out tuples and maps are data, not calls" do
    """
    config :app, :trigger, nil
    # reconciler MFA to enable auto-recovery:
    #   {Megalith.AgeOps.Reconciler, :handle_event, []}
    #   %{a: 1}
    """
    |> run()
    |> refute_issues()
  end

  test "a prose lead-in followed by one commented config line is not flagged" do
    """
    # Set the trigger to enable auto-recovery:
    #   config :app, :trigger,
    #     {Reconciler, :handle_event, []}
    config :app, :trigger, nil
    """
    |> run()
    |> refute_issues()
  end

  test "generated documentation examples are skipped unless the prose says the code is disabled" do
    """
    # ## SSL Support
    #
    # To get SSL working, you will need to add the `https` key
    # to your endpoint configuration:
    #
    #     config :app, App.Endpoint,
    #       https: [port: 4001]
    config :app, :x, 1
    """
    |> run()
    |> refute_issues()

    """
    # Disabled until the migration completes:
    # relationships do
    #   belongs_to :tenant, Tenant
    # end
    config :app, :x, 1
    """
    |> run()
    |> assert_issue()
  end

  test "the generated router's custom stacks scaffold is not commented-out code" do
    """
    defmodule MyAppWeb.Router do
      # Other scopes may use custom stacks.
      # scope "/api", MyAppWeb do
      #   pipe_through :api
      # end
    end
    """
    |> run()
    |> refute_issues()
  end
end
