defmodule Extreme.System.AggregateRegistry do
  @moduledoc """
  Keeps track of registered aggregate pids.
  """

  require Logger
  use GenServer

  def name(aggregate_mod), do: "#{aggregate_mod}.PidRegistry"  |> String.to_atom

  ## Client API

  @doc """
  Starts process registry
  """
  def start_link(name), 
    do: GenServer.start_link(__MODULE__, name, name: name)

  @doc """
  Returns `true` if `key` is already registered in `server`, `false` otherwise.
  """
  def has_key?(server, key), do: GenServer.call(server, {:has_key?, key})

  @doc """
  Looks up the process pid for `id` stored in `server`.

  Returns `{:ok, pid}` if the one exists, `:error` otherwise.
  """
  def get(server, key), 
    do: _get(server, key)


  @doc """
  Ensures there is a `pid` associated with `key` in `server`.

  Returns :ok once when process is successfully registered
  """
  def register(server, key, pid), do: GenServer.call(server, {:register, key, pid})


  ## Server Callbacks

  def init(name) do 
    name
    |> pid_table
    |> :ets.new([:named_table, read_concurrency: true])
    name
    |> ref_table
    |> :ets.new([:named_table, read_concurrency: true])

    {:ok, %{pid_table: pid_table(name), ref_table: ref_table(name)}}
  end

  ## Private functions

  defp _get(server, key) do
    case :ets.lookup(pid_table(server), key) do
      [{^key, val}] -> {:ok, val}
      []            -> :error
    end
  end

  defp pid_table(name), do: "#{name}.Pids" |> String.to_atom
  defp ref_table(name), do: "#{name}.Refs" |> String.to_atom


  def handle_call({:has_key?, key}, _from, state) do
    {:reply, Map.has_key?(state.processes, key), state}
  end

  def handle_call({:get, key}, _from, state) do
    {:reply, Map.fetch(state.processes, key), state}
  end

  def handle_call({:register, key, pid}, _from, state) do
    state = case _get(state.table, key) do
      {:ok, pid} -> {:ok, state}
      :error     ->
        ref   = Process.monitor pid
        true = :ets.insert state.table, {key, pid}
    end
    {:reply, :ok, state}
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    {id, refs} = Map.pop(state.refs, ref)
    processes = Map.delete(state.processes, id)
    {:noreply, %{state | processes: processes, refs: refs}}
  end
  def handle_info(_msg, state), do: {:noreply, state}
end
