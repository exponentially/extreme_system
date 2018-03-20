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

  handle_cmd :timeout, val, metadata, fn
    from, _, state ->
      :timer.sleep 500
      {:noblock, from, state.msg, state}
  end, 200


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
    {:ok, %{msg: "something"}} = Aggregate.commit a, transaction_id, version, version
    assert Aggregate.message(a) == "something"
  end

  test "returns {:ok, state.version} if dry_run is set to true", %{a: a} do
    assert Aggregate.message(a) == ""
    assert {:ok, -1} = Aggregate.do_something(a, %{"key" => "something", "dry_run" => true}, [user: 123])
    assert Aggregate.message(a) == ""
  end

  test "returns {:ok, events} if dry_run is set to :verbose", %{a: a} do
    assert Aggregate.message(a) == ""
    assert {:ok, [%{val: %{"key" => "something"}}]} = 
           Aggregate.do_something(a, %{"key" => "something", "dry_run" => :verbose}, [user: 123])
    assert Aggregate.message(a) == ""
  end

  test "can return customized response if everything is ok", %{a: a} do
    assert {:ok, transaction_id, _events, version, :customized_response} = Aggregate.do_with_customized_response(a, "cust")
    {:ok, %{msg: "cust"}} = Aggregate.commit a, transaction_id, version, version
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
        {:ok, _} = Aggregate.commit a, transaction_id_2, version, version + 1
      end
    end
    :timer.sleep 10
    {:ok, transaction_id_1, _, version, _} = Aggregate.do_something(a, "else ")
    for n <- 6..9 do
      :timer.sleep 10
      spawn fn ->
        {:ok, transaction_id_2, _, version, _} = Aggregate.do_something(a, "#{n} ")
        {:ok, _} = Aggregate.commit a, transaction_id_2, version, version + 1
      end
    end
    {:ok, _} = Aggregate.commit a, transaction_id_1, version, version + 1
    assert Aggregate.message(a) == "1 2 3 4 5 else 6 7 8 9 "
  end

  test "exec timeout", %{a: a} do
    spawn_link fn -> Aggregate.timeout(a, :whatever) end
    Process.flag :trap_exit, true
    assert_receive {:EXIT, _, {:timeout, {GenServer, :call, [^a, _, 200]}}}, 300
  end

  test "commit timeout", %{a: a} do
    {:ok, transaction_id_1, _, version, _} = Aggregate.do_something(a, "1 ")
    {:ok, _} = Aggregate.commit a, transaction_id_1, version, version
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

  test ":noblock response doesn't block further buffer execution, causing client to timeout" do
    {:ok, a} = Aggregate.start_link
    for n <- 1..3 do
      spawn fn ->
        {:ok, transaction_id, _events, version, _} = Aggregate.do_something(a, "#{n} ")
        :timer.sleep 1_000
        {:ok, _} = Aggregate.commit a, transaction_id, version, version + 1
      end
      :timer.sleep 10
    end
    spawn fn ->
      assert Aggregate.message(a) == "1 2 3 "
    end
    :timer.sleep 10
    spawn fn ->
      {:ok, transaction_id, _events, version, _} = Aggregate.do_something(a, "last")
      {:ok, _} = Aggregate.commit a, transaction_id, version, version + 1
    end
    :timer.sleep 10
    assert Aggregate.message(a) == "1 2 3 last"
  end


  defp assert_down(a, wait_time) do
    Process.flag :trap_exit, true
    ref = Process.monitor a
    {_, _, _, _, {:commit_timeout, _state}=reason} = assert_receive {:DOWN, ^ref, _, _, _}, wait_time
    {:down, reason}
  end
end
