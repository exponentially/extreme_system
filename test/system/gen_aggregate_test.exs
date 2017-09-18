defmodule Aggregate do
  use     Extreme.System.GenAggregate
  require Logger

  defmodule State, 
    do: defstruct GenAggregate.state_params ++ 
        [:msg]


  def start_link(ttl \\ 2_000), do: GenAggregate.start_link __MODULE__, ttl

  def init(ttl),
    do: {:ok, struct(State, initial_state(ttl) |> Map.put(:msg, ""))}


  handle_cmd :do_something, val, metadata, fn
    from, _, state ->
      events = [%{val: val}]
      {:block, from, {:events, events}, state}
  end

  handle_cmd :do_with_customized_response, val, metadata, fn
    from, _, state ->
      events = [%{val: val}]
      {:block, from, {:events, events, :customized_response}, state}
  end

  handle_cmd :message, fn
    from, state ->
      {:noblock, from, state.msg, state}
  end


  defp apply_event(%{val: val}, state),
    do: %{ state | msg: state.msg <> val }
  defp apply_event(_, state),
    do: state
end

defmodule Extreme.System.GenAggregateTest do
  use     ExUnit.Case, async: true
  doctest Extreme.System.GenAggregate

  setup do
    {:ok, a} = Aggregate.start_link
    {:ok, %{a: a}}
  end

  test "can commit active transaction", %{a: a} do
    {:ok, transaction_id, _events, version, _} = Aggregate.do_something(a, "something", [user: 123])
    :ok = Aggregate.commit a, transaction_id, version, version
    assert Aggregate.message(a) == "something"
  end

  test "can return customized response if everything is ok", %{a: a} do
    assert {:ok, transaction_id, _events, version, :customized_response} = Aggregate.do_with_customized_response(a, "cust")
    :ok = Aggregate.commit a, transaction_id, version, version
    assert Aggregate.message(a) == "cust"
  end

  test "can't commit nil transaction", %{a: a} do
    assert {:error, :nil_transaction} =  Aggregate.commit(a, nil, 1, 1)
  end

  test "can't commit wrong transaction", %{a: a} do
    {:ok, _, _, version, _} = Aggregate.do_something(a, "something")
    assert {:error, :wrong_transaction} = Aggregate.commit(a, "wrong_transaction", version, version + 1)
  end

  test "waits with second command until first is commited", %{a: a} do
    for n <- 1..5 do
      :timer.sleep 10
      spawn fn ->
        {:ok, transaction_id_2, _events, version, _} = Aggregate.do_something(a, "#{n} ")
        :timer.sleep n * 100
        :ok = Aggregate.commit a, transaction_id_2, version, version + 1
      end
    end
    :timer.sleep 10
    {:ok, transaction_id_1, _, version, _} = Aggregate.do_something(a, "else ")
    for n <- 6..9 do
      :timer.sleep 10
      spawn fn ->
        {:ok, transaction_id_2, _, version, _} = Aggregate.do_something(a, "#{n} ")
        :ok = Aggregate.commit a, transaction_id_2, version, version + 1
      end
    end
    :ok = Aggregate.commit a, transaction_id_1, version, version + 1
    assert Aggregate.message(a) == "1 2 3 4 5 else 6 7 8 9 "
  end

  test "timeout", %{a: a} do
    {:ok, transaction_id_1, _, version, _} = Aggregate.do_something(a, "1 ")
    :ok = Aggregate.commit a, transaction_id_1, version, version
    assert Aggregate.message(a) == "1 "

    #should timeout after 2 sec
    {:ok, transaction_id_3, _, _, _} = Aggregate.do_something(a, "throw_away")
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
    assert {:error, :wrong_transaction} = Aggregate.commit(a, transaction_id_3, -1, 2)
  end

  defp assert_down(a, wait_time) do
    Process.flag :trap_exit, true
    ref = Process.monitor a
    {_, _, _, _, {:commit_timeout, _state}=reason} = assert_receive {:DOWN, ^ref, _, _, _}, wait_time
    {:down, reason}
  end
end
