defmodule OptimumCredo.Check.Warning.CallerModuleAttributesTest do
  use Credo.Test.Case, async: true

  alias OptimumCredo.Check.Warning.CallerModuleAttributes

  test "it reports generic attributes in a Boundary-style definition quote" do
    """
    defmodule Boundary.Definition do
      def generate(opts, env) do
        quote bind_quoted: [opts: opts, pos: env.file, app: env.module] do
          @opts opts
          @pos pos
          @app app
        end
      end
    end
    """
    |> to_source_file()
    |> run_check(CallerModuleAttributes)
    |> assert_issues(fn issues ->
      assert length(issues) == 3
      messages = Enum.map(issues, & &1.message)
      assert Enum.any?(messages, &String.contains?(&1, "@opts"))
      assert Enum.any?(messages, &String.contains?(&1, "@pos"))
      assert Enum.any?(messages, &String.contains?(&1, "@app"))
    end)
  end

  test "it scans quote options before bind_quoted and Spark-style quote bodies" do
    """
    defmodule Spark.Dsl do
      defmacro configure(opts) do
        quote bind_quoted: [opts: opts] do
          @opts opts
        end
      end
    end
    """
    |> to_source_file()
    |> run_check(CallerModuleAttributes)
    |> assert_issue(fn issue ->
      assert issue.message =~ "@opts"
    end)
  end

  test "it ignores module-owned attributes, built-ins, and nested generated modules" do
    """
    defmodule Boundary.Definition do
      @opts [:owned_by_this_library]

      defmacro __using__(_opts) do
        quote do
          @before_compile __MODULE__
          @doc false
          @spec generated() :: :ok
          @__boundary_definition_opts__ unquote(@opts)

          defmodule GeneratedChild do
            @opts [:owned_by_generated_child]
          end
        end
      end
    end
    """
    |> to_source_file()
    |> run_check(CallerModuleAttributes)
    |> refute_issues()
  end

  test "it does not resolve AST returned by unquote expressions" do
    """
    defmodule Boundary.Definition do
      def generate(_opts) do
        quote do
          unquote(quote(do: @opts))
          unquote_splicing([quote(do: @app)])
        end
      end
    end
    """
    |> to_source_file()
    |> run_check(CallerModuleAttributes)
    |> refute_issues()
  end

  test "a leading underscore without an owner namespace still warns" do
    """
    defmodule Boundary.Definition do
      defmacro __using__(_opts) do
        quote do
          @_opts :generic
          @__boundary_definition_opts__ :owned
        end
      end
    end
    """
    |> to_source_file()
    |> run_check(CallerModuleAttributes)
    |> assert_issue(fn issue ->
      assert issue.message =~ "@_opts"
    end)
  end

  test "a nested lexical module keeps its outer library prefix" do
    """
    defmodule MyLibrary do
      defmodule Adapter do
        defmacro __using__(_opts) do
          quote do
            @__my_library_adapter_opts__ []
          end
        end
      end
    end
    """
    |> to_source_file()
    |> run_check(CallerModuleAttributes)
    |> refute_issues()
  end

  test "required_prefix allows private attributes that name their owner" do
    """
    defmodule MyLibrary.Macros do
      defmacro __using__(_opts) do
        quote do
          @__my_library_opts__ []
          @_opts []
        end
      end
    end
    """
    |> to_source_file()
    |> run_check(CallerModuleAttributes, required_prefix: "my_library")
    |> assert_issue(fn issue ->
      assert issue.message =~ "@_opts"
    end)
  end

  test "allow_attributes permits documented public caller configuration" do
    """
    defmodule MyLibrary.Macros do
      defmacro __using__(_opts) do
        quote do
          @public_config []
          @other_public_config []
        end
      end
    end
    """
    |> to_source_file()
    |> run_check(CallerModuleAttributes, allow_attributes: [:other_public_config])
    |> assert_issue(fn issue ->
      assert issue.message =~ "@public_config"
    end)
  end

  test "literal Module attribute APIs targeting the caller are checked" do
    """
    defmodule Boundary.Definition do
      defmacro __using__(_opts) do
        quote do
          Module.register_attribute(__MODULE__, :opts, persist: true)
          Module.put_attribute(__MODULE__, :app, :example)
          Module.get_attribute(__MODULE__, :pos)
        end
      end
    end
    """
    |> to_source_file()
    |> run_check(CallerModuleAttributes)
    |> assert_issues(fn issues ->
      assert length(issues) == 3
      messages = Enum.map(issues, & &1.message)
      assert Enum.any?(messages, &String.contains?(&1, "@opts"))
      assert Enum.any?(messages, &String.contains?(&1, "@app"))
      assert Enum.any?(messages, &String.contains?(&1, "@pos"))
    end)
  end

  test "literal Module attribute APIs targeting __CALLER__ are checked" do
    """
    defmodule Boundary.Definition do
      defmacro __using__(opts) do
        Module.put_attribute(__CALLER__.module, :opts, opts)
        Module.register_attribute(__CALLER__.module, :app, persist: true)

        quote do
          :ok
        end
      end
    end
    """
    |> to_source_file()
    |> run_check(CallerModuleAttributes)
    |> assert_issues(fn issues ->
      assert length(issues) == 2
      messages = Enum.map(issues, & &1.message)
      assert Enum.any?(messages, &String.contains?(&1, "@opts"))
      assert Enum.any?(messages, &String.contains?(&1, "@app"))
    end)
  end

  test "Module attribute APIs targeting the library module are ignored outside quotes" do
    """
    defmodule Boundary.Definition do
      Module.register_attribute(__MODULE__, :opts, persist: true)
      Module.put_attribute(__MODULE__, :app, :library_state)
      Module.get_attribute(__MODULE__, :pos)
    end
    """
    |> to_source_file()
    |> run_check(CallerModuleAttributes)
    |> refute_issues()
  end

  test "attribute API calls with non-caller or dynamic targets are outside the heuristic" do
    """
    defmodule Boundary.Definition do
      defmacro __using__(target) do
        quote do
          Module.put_attribute(SomeOtherModule, :opts, [])
          Module.put_attribute(target, :app, :example)
        end
      end
    end
    """
    |> to_source_file()
    |> run_check(CallerModuleAttributes)
    |> refute_issues()
  end
end
