defmodule OptimumCredo.Check.Readability.ModuleSelfPrefixTest do
  use Credo.Test.Case, async: true

  alias OptimumCredo.Check.Readability.ModuleSelfPrefix

  test "reports prefixed calls to local public and private functions" do
    """
    defmodule Demo do
      def run(x), do: __MODULE__.helper(x) + __MODULE__.private(x)
      def helper(x), do: x
      defp private(x), do: x
    end
    """
    |> to_source_file()
    |> run_check(ModuleSelfPrefix)
    |> assert_issues(fn issues ->
      assert Enum.map(issues, & &1.line_no) == [2, 2]
      assert hd(issues).message =~ "helper"
    end)
  end

  test "reports pipes, captures and nested arguments" do
    """
    defmodule Demo do
      def run(list) do
        list |> Enum.map(&__MODULE__.helper/1) |> __MODULE__.helper()
      end

      def helper(x), do: __MODULE__.helper(__MODULE__.helper(x))
    end
    """
    |> to_source_file()
    |> run_check(ModuleSelfPrefix)
    |> assert_issues(fn issues -> assert length(issues) == 4 end)
  end

  test "ignores struct literals, child aliases, unknown functions and other modules" do
    """
    defmodule Demo do
      defstruct [:a]

      def run(x) do
        _ = %__MODULE__{a: x}
        _ = __MODULE__.Child.build()
        _ = __MODULE__.__struct__()
        _ = __MODULE__.injected_by_use()
        _ = Other.helper(x)
        helper(x)
      end

      def helper(x), do: x
    end
    """
    |> to_source_file()
    |> run_check(ModuleSelfPrefix)
    |> refute_issues()
  end

  test "nested modules and quote blocks keep their own __MODULE__" do
    """
    defmodule Demo do
      def helper(x), do: x

      defmodule Inner do
        def run(x), do: __MODULE__.helper(x)
        def helper(x), do: x
      end

      defmacro __using__(_opts) do
        quote do
          def run(x), do: __MODULE__.helper(x)
        end
      end
    end
    """
    |> to_source_file()
    |> run_check(ModuleSelfPrefix)
    |> assert_issue(fn issue -> assert issue.line_no == 5 end)
  end

  test "allow_self_prefix_for accepts atoms and strings" do
    source = """
    defmodule Demo do
      def run(x), do: __MODULE__.helper(x) + __MODULE__.other(x)
      def helper(x), do: x
      def other(x), do: x
    end
    """

    source
    |> to_source_file()
    |> run_check(ModuleSelfPrefix, allow_self_prefix_for: [:helper, "other"])
    |> refute_issues()

    source
    |> to_source_file()
    |> run_check(ModuleSelfPrefix, allow_self_prefix_for: [:helper])
    |> assert_issue(fn issue -> assert issue.message =~ "other" end)
  end

  test "ignores strings and docs mentioning the prefix" do
    ~S'''
    defmodule Demo do
      @moduledoc "Do not write __MODULE__.helper(x)"
      def run, do: "__MODULE__.helper()"
      def helper, do: :ok
    end
    '''
    |> to_source_file()
    |> run_check(ModuleSelfPrefix)
    |> refute_issues()
  end

  test "matches by name and arity, counting piped values and default arguments" do
    """
    defmodule Demo do
      def run(x) do
        a = __MODULE__.helper(x, 1)
        b = x |> __MODULE__.helper()
        c = __MODULE__.helper(x)
        d = __MODULE__.opt(x)
        e = __MODULE__.opt(x, 1)
        {a, b, c, d, e}
      end

      def helper(x), do: x
      def opt(x, y \\\\ 1), do: {x, y}
    end
    """
    |> to_source_file()
    |> run_check(ModuleSelfPrefix)
    |> assert_issues(fn issues ->
      assert Enum.map(issues, & &1.line_no) == [4, 5, 6, 7]
    end)
  end

  test "a same-named function of another arity is not local" do
    """
    defmodule Demo do
      def run(x), do: __MODULE__.fetch(x, 1, 2)
      def fetch(x), do: x
    end
    """
    |> to_source_file()
    |> run_check(ModuleSelfPrefix)
    |> refute_issues()
  end

  test "captures are matched by their written arity" do
    """
    defmodule Demo do
      def run(list) do
        Enum.map(list, &__MODULE__.double/1) ++ Enum.map(list, &__MODULE__.double/2)
      end

      def double(x), do: x * 2
    end
    """
    |> to_source_file()
    |> run_check(ModuleSelfPrefix)
    |> assert_issue(fn issue -> assert issue.message =~ "double" end)
  end

  test "macros are not reported because they must be defined before use" do
    """
    defmodule Demo do
      defmacro twice(x), do: quote(do: unquote(x) * 2)
      def run(x), do: __MODULE__.twice(x)
    end
    """
    |> to_source_file()
    |> run_check(ModuleSelfPrefix)
    |> refute_issues()
  end

  test "reports delegated functions and parenless zero-arity definitions" do
    """
    defmodule Demo do
      defdelegate fetch(key), to: Map
      def now, do: 1
      def run(key), do: {__MODULE__.fetch(key), __MODULE__.now()}
    end
    """
    |> to_source_file()
    |> run_check(ModuleSelfPrefix)
    |> assert_issues(fn issues -> assert length(issues) == 2 end)
  end

  test "module-level uses such as defstruct defaults and attributes keep the prefix" do
    """
    defmodule Demo do
      defstruct formatter: &__MODULE__.format/1

      @default __MODULE__.format(1)

      def format(x), do: x
      def run(x), do: __MODULE__.format(x)
    end
    """
    |> to_source_file()
    |> run_check(ModuleSelfPrefix)
    |> assert_issue(fn issue -> assert issue.line_no == 7 end)
  end

  test "reports prefixed calls in rescue and after blocks" do
    """
    defmodule Demo do
      def check(x), do: x
      def run(x) do
        __MODULE__.check(x)
      rescue
        _ -> __MODULE__.check(x)
      after
        __MODULE__.check(x)
      end
    end
    """
    |> to_source_file()
    |> run_check(ModuleSelfPrefix)
    |> assert_issues(fn issues -> assert Enum.map(issues, & &1.line_no) == [4, 6, 8] end)
  end

  test "does not advise dropping the prefix for Kernel function and macro collisions" do
    """
    defmodule Demo do
      def inspect(value), do: value
      def to_string(value), do: value
      def send(a, b), do: {a, b}
      def max(a, b), do: {a, b}
      def if(a, b), do: {a, b}

      def run(v) do
        {__MODULE__.inspect(v), __MODULE__.to_string(v), __MODULE__.send(v, v),
         v |> __MODULE__.max(v), &__MODULE__.if/2}
      end
    end
    """
    |> to_source_file()
    |> run_check(ModuleSelfPrefix)
    |> refute_issues()
  end

  test "still reports local functions that only share a name with Kernel at another arity" do
    """
    defmodule Demo do
      def inspect(a, b, c, d), do: {a, b, c, d}
      def run(v), do: __MODULE__.inspect(v, v, v, v)
    end
    """
    |> to_source_file()
    |> run_check(ModuleSelfPrefix)
    |> assert_issue(fn issue -> assert issue.message =~ "inspect" end)
  end

  test "reports a real unshadowed self-call next to a Kernel collision" do
    """
    defmodule Demo do
      def inspect(value), do: value
      def helper(value), do: value
      def run(v), do: {__MODULE__.inspect(v), __MODULE__.helper(v)}
    end
    """
    |> to_source_file()
    |> run_check(ModuleSelfPrefix)
    |> assert_issue(fn issue -> assert issue.message =~ "helper" end)
  end

  test "reports Kernel-named locals when import Kernel except removes that name and arity" do
    """
    defmodule Demo do
      import Kernel, except: [inspect: 1]

      def inspect(value), do: value
      def to_string(value), do: value
      def run(v), do: {__MODULE__.inspect(v), __MODULE__.to_string(v)}
    end
    """
    |> to_source_file()
    |> run_check(ModuleSelfPrefix)
    |> assert_issue(fn issue ->
      assert issue.message =~ "inspect"
      refute issue.message =~ "to_string"
    end)
  end

  test "an import except for another arity does not remove the collision" do
    """
    defmodule Demo do
      import Kernel, except: [inspect: 2]

      def inspect(value), do: value
      def run(v), do: __MODULE__.inspect(v)
    end
    """
    |> to_source_file()
    |> run_check(ModuleSelfPrefix)
    |> refute_issues()
  end

  test "import Kernel only removes names it does not list" do
    """
    defmodule Demo do
      import Kernel, only: [to_string: 1]

      def inspect(value), do: value
      def to_string(value), do: value
      def run(v), do: {__MODULE__.inspect(v), __MODULE__.to_string(v)}
    end
    """
    |> to_source_file()
    |> run_check(ModuleSelfPrefix)
    |> assert_issue(fn issue -> assert issue.message =~ "inspect" end)
  end

  test "import Kernel except is scoped to its own module and applies to nested modules" do
    """
    defmodule Outer do
      def inspect(value), do: value
      def run(v), do: __MODULE__.inspect(v)

      defmodule Inner do
        import Kernel, except: [inspect: 1]

        def inspect(value), do: value
        def run(v), do: __MODULE__.inspect(v)

        defmodule Deeper do
          def inspect(value), do: value
          def run(v), do: __MODULE__.inspect(v)
        end
      end
    end
    """
    |> to_source_file()
    |> run_check(ModuleSelfPrefix)
    |> assert_issues(fn issues -> assert Enum.map(issues, & &1.line_no) == [9, 13] end)
  end
end
