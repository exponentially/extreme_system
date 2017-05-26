defmodule Aggregate do
  use     Extreme.System.GenAggregate
  require Logger

  defmodule State, do: defstruct [:transaction, :ttl, :events, :buffer, :msg]

  ## Client API

  def start_link(ttl \\ 2_000), do: GenAggregate.start_link __MODULE__, ttl

  def do_something(pid, val) do 
    Logger.debug "Try #{val}"
    exec pid, {:do_something, val}
  end

  def message(pid), do: exec pid, :get_message


  ## Server Callbacks

  def init(ttl), do: {:ok, %State{events: [], buffer: [], msg: "", ttl: ttl}}

  def handle_exec({:do_something, val}, from, state) do
    Logger.debug "Doing #{val}"
    events = [%{val: val}]
    {:block, from, {:events, events}, state}
  end
  def handle_exec(:get_message, from, state) do
    {:noblock, from, state.msg, state}
  end

  defp apply_events([%{val: val} | tail], state) do
    state = %{ state | msg: state.msg <> val }
    apply_events tail, state
  end
end

defmodule Extreme.System.GenAggregateTest do
  use     ExUnit.Case, async: true
  doctest Extreme.System.GenAggregate

  setup do
    {:ok, a} = Aggregate.start_link
    {:ok, %{a: a}}
  end

  test "can commit active transaction", %{a: a} do
    {:ok, transaction_id, _} = Aggregate.do_something(a, "something")
    :ok = Aggregate.commit a, transaction_id
    assert Aggregate.message(a) == "something"
  end

  test "can't commit nil transaction", %{a: a} do
    assert {:error, :nil_transaction} =  Aggregate.commit(a, nil)
  end

  test "can't commit wrong transaction", %{a: a} do
    {:ok, _, _} = Aggregate.do_something(a, "something")
    assert {:error, :wrong_transaction} =  Aggregate.commit(a, :wrong_transaction)
  end

  test "waits with second command until first is commited", %{a: a} do
    for n <- 1..5 do
      :timer.sleep 10
      spawn fn ->
        {:ok, transaction_id_2, _} = Aggregate.do_something(a, "#{n} ")
        :timer.sleep n * 100
        :ok = Aggregate.commit a, transaction_id_2
      end
    end
    :timer.sleep 10
    {:ok, transaction_id_1, _} = Aggregate.do_something(a, "else ")
    for n <- 6..9 do
      :timer.sleep 10
      spawn fn ->
        {:ok, transaction_id_2, _} = Aggregate.do_something(a, "#{n} ")
        :ok = Aggregate.commit a, transaction_id_2
      end
    end
    :ok = Aggregate.commit a, transaction_id_1 
    assert Aggregate.message(a) == "1 2 3 4 5 else 6 7 8 9 "
  end

  test "timeout", %{a: a} do
    {:ok, transaction_id_1, _} = Aggregate.do_something(a, "1 ")
    :ok = Aggregate.commit a, transaction_id_1
    assert Aggregate.message(a) == "1 "

    #should timeout after 2 sec
    {:ok, transaction_id_3, _} = Aggregate.do_something(a, "throw_away")
    for n <- 2..5 do
      :timer.sleep 10
      spawn fn ->
        Aggregate.do_something(a, "#{n} ")
      end
    end

    {:down, {:commit_timeout, state}} = assert_down a, 3_000
    #assert that there are 4 unprocessed commands in buffer
    assert Enum.count(state.buffer) == 4

    {:ok, a} = Aggregate.start_link
    assert {:error, :wrong_transaction} = Aggregate.commit(a, transaction_id_3)
  end

  defp assert_down(a, wait_time) do
    Process.flag :trap_exit, true
    ref = Process.monitor a
    {_, _, _, _, {:commit_timeout, _state}=reason} = assert_receive {:DOWN, ^ref, _, _, _}, wait_time
    {:down, reason}
  end
end
