defmodule OptimumCredo.Check.Readability.SingleElementTupleMessageTest do
  use Credo.Test.Case, async: true

  alias OptimumCredo.Check.Readability.SingleElementTupleMessage

  test "reports send, Process.send and Process.send_after with one-element tuples" do
    """
    defmodule Sample do
      def run(pid) do
        send(pid, {:refresh})
        pid |> send({:refresh})
        Process.send(pid, {:refresh}, [])
        Process.send_after(self(), {:tick}, 100)
        self() |> Process.send_after({:tick}, 100)
      end
    end
    """
    |> to_source_file()
    |> run_check(SingleElementTupleMessage)
    |> assert_issues(fn issues -> assert length(issues) == 5 end)
  end

  test "allows atoms, larger tuples, variables and other functions" do
    """
    defmodule Sample do
      def run(pid, msg) do
        send(pid, :refresh)
        send(pid, {:refresh, 1})
        send(pid, {})
        send(pid, msg)
        GenServer.cast(pid, {:refresh})
        notify(pid, {:refresh})
        Process.send_after(pid, :tick, 100)
        send({:refresh}, pid)
      end
    end
    """
    |> to_source_file()
    |> run_check(SingleElementTupleMessage)
    |> refute_issues()
  end

  test "ignores strings and comments" do
    ~S'''
    defmodule Sample do
      # send(pid, {:refresh})
      def run, do: "send(pid, {:refresh})"
    end
    '''
    |> to_source_file()
    |> run_check(SingleElementTupleMessage)
    |> refute_issues()
  end

  test "does not report definitions, non-atom elements or look-alike arities" do
    """
    defmodule Sample do
      defp send(pid, {:refresh}), do: pid
      @spec send(pid(), {:ok}) :: :ok
      def run(pid, ref, value) do
        send(self(), {ref})
        send(pid, {value})
        send(pid, {:ok}, [:nosuspend])
        Process.send(pid, {value}, [])
        Process.send_after(pid, {ref}, 100)
        :ok
      end
    end
    """
    |> to_source_file()
    |> run_check(SingleElementTupleMessage)
    |> refute_issues()
  end

  test "reports Kernel.send and Process.send with the right arity, including piped forms" do
    """
    defmodule Sample do
      def run(pid) do
        Kernel.send(pid, {:a})
        Process.send(pid, {:b}, [:noconnect])
        pid |> Process.send_after({:c}, 100)
        {:d} |> then(&send(pid, &1))
        Process.send_after(pid, {:e}, 100, abs: true)
        :ok
      end
    end
    """
    |> to_source_file()
    |> run_check(SingleElementTupleMessage)
    |> assert_issues(fn issues -> assert Enum.map(issues, & &1.line_no) == [3, 4, 5, 7] end)
  end
end
