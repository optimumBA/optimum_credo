defmodule OptimumCredo.Check.Readability.PrivateFunctionSpecsTest do
  use Credo.Test.Case

  alias OptimumCredo.Check.Readability.PrivateFunctionSpecs

  test "it should NOT report public functions with specs" do
    """
    defmodule MyModule do
      @spec process_data(map()) :: :ok
      def process_data(_data), do: :ok

      @spec get_result() :: String.t()
      def get_result, do: "result"
    end
    """
    |> to_source_file()
    |> run_check(PrivateFunctionSpecs)
    |> refute_issues()
  end

  test "it should NOT report private functions without specs" do
    """
    defmodule MyModule do
      def public_function, do: helper_function()

      defp helper_function, do: :ok
    end
    """
    |> to_source_file()
    |> run_check(PrivateFunctionSpecs)
    |> refute_issues()
  end

  test "it should report private functions with specs" do
    """
    defmodule MyModule do
      @spec lookup_cached_entries(list()) :: {:hit, String.t()} | :miss
      defp lookup_cached_entries(ets_match_spec) do
        :miss
      end
    end
    """
    |> to_source_file()
    |> run_check(PrivateFunctionSpecs)
    |> assert_issue(fn issue ->
      assert issue.message =~ "Remove @spec for private function lookup_cached_entries"
      assert issue.message =~ "Private functions should not have @spec declarations"
    end)
  end

  test "it should report multiple private functions with specs" do
    """
    defmodule MyModule do
      @spec helper_one(String.t()) :: String.t()
      defp helper_one(input), do: input

      @spec helper_two(integer()) :: integer()
      defp helper_two(num), do: num
    end
    """
    |> to_source_file()
    |> run_check(PrivateFunctionSpecs)
    |> assert_issues(fn issues ->
      assert length(issues) == 2
      messages = Enum.map(issues, & &1.message)
      assert Enum.any?(messages, &String.contains?(&1, "helper_one"))
      assert Enum.any?(messages, &String.contains?(&1, "helper_two"))
    end)
  end

  test "it should handle mixed public and private functions" do
    """
    defmodule MyModule do
      @spec public_function(String.t()) :: String.t()
      def public_function(input) do
        private_helper(input)
      end

      @spec private_helper(String.t()) :: String.t()
      defp private_helper(input), do: String.upcase(input)
    end
    """
    |> to_source_file()
    |> run_check(PrivateFunctionSpecs)
    |> assert_issue(fn issue ->
      assert issue.message =~ "Remove @spec for private function private_helper"
    end)
  end

  test "it should handle specs with complex types" do
    """
    defmodule MyModule do
      @spec complex_private({:ok, String.t()} | {:error, atom()}) :: boolean()
      defp complex_private({:ok, _}), do: true
      defp complex_private({:error, _}), do: false
    end
    """
    |> to_source_file()
    |> run_check(PrivateFunctionSpecs)
    |> assert_issue(fn issue ->
      assert issue.message =~ "Remove @spec for private function complex_private"
    end)
  end

  test "it should handle functions with different arities" do
    """
    defmodule MyModule do
      @spec helper() :: :ok
      defp helper, do: :ok

      @spec helper(String.t()) :: String.t()
      defp helper(input), do: input

      @spec helper(String.t(), integer()) :: String.t()
      defp helper(input, count), do: String.duplicate(input, count)
    end
    """
    |> to_source_file()
    |> run_check(PrivateFunctionSpecs)
    |> assert_issues(fn issues ->
      assert length(issues) == 3
      messages = Enum.map(issues, & &1.message)
      assert Enum.all?(messages, &String.contains?(&1, "helper/"))
    end)
  end

  test "it should include arity in error message" do
    """
    defmodule MyModule do
      @spec process_item(String.t(), map(), keyword()) :: :ok
      defp process_item(_item, _data, _opts), do: :ok
    end
    """
    |> to_source_file()
    |> run_check(PrivateFunctionSpecs)
    |> assert_issue(fn issue ->
      assert issue.message =~ "process_item/3"
    end)
  end

  test "it should handle specs separated by comments from private functions" do
    """
    defmodule MyModule do
      @spec internal_process(map()) :: :ok
      # This is a helper function
      defp internal_process(_data), do: :ok
    end
    """
    |> to_source_file()
    |> run_check(PrivateFunctionSpecs)
    |> assert_issue(fn issue ->
      assert issue.message =~ "Remove @spec for private function internal_process"
    end)
  end

  test "it should NOT match specs too far from private functions" do
    """
    defmodule MyModule do
      @spec some_function(map()) :: :ok
      def some_function(_data), do: :ok

      def another_function, do: :ok

      # This defp is far from the spec above
      defp different_function, do: :ok
    end
    """
    |> to_source_file()
    |> run_check(PrivateFunctionSpecs)
    |> refute_issues()
  end

  test "it should handle functions with guards" do
    """
    defmodule MyModule do
      @spec guarded_private(integer()) :: atom()
      defp guarded_private(n) when is_integer(n), do: :ok
    end
    """
    |> to_source_file()
    |> run_check(PrivateFunctionSpecs)
    |> assert_issue(fn issue ->
      assert issue.message =~ "Remove @spec for private function guarded_private"
    end)
  end

  test "it should handle modules without any functions" do
    """
    defmodule MyModule do
      @moduledoc "Empty module"
    end
    """
    |> to_source_file()
    |> run_check(PrivateFunctionSpecs)
    |> refute_issues()
  end
end
