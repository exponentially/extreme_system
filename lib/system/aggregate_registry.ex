defmodule Extreme.System.AggregateRegistry do
  @moduledoc """
  Keeps track of registered aggregate pids.
  """

  require Logger
  use GenServer

  def name(aggregate_mod), do: "#{aggregate_mod}.PidRegistry" |> String.to_atom()

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
    do: server |> pid_table |> _get(key)

  @doc """
  Ensures there is a `pid` associated with `key` in `server`.

  Returns :ok once when process is successfully registered
  """
  def register(server, key, pid),
    do: GenServer.call(server, {:register, key, pid})

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

  defp _get(table, key) do
    case :ets.lookup(table, key) do
      [{^key, val}] -> {:ok, val}
      [] -> :error
    end
  end

  defp pid_table(name), do: "#{name}.Pids" |> String.to_atom()
  defp ref_table(name), do: "#{name}.Refs" |> String.to_atom()

  def handle_call({:has_key?, key}, _from, state) do
    {:reply, Map.has_key?(state.processes, key), state}
  end

  def handle_call({:get, key}, _from, state) do
    {:reply, Map.fetch(state.processes, key), state}
  end

  def handle_call({:register, key, pid}, _from, state) do
    result =
      case _get(state.pid_table, key) do
        {:ok, pid} ->
          {:error, :key_already_registered, pid}

        :error ->
          ref = Process.monitor(pid)
          true = :ets.insert(state.pid_table, {key, pid})
          true = :ets.insert(state.ref_table, {ref, key})
          :ok
      end

    {:reply, result, state}
  end

  def handle_info({:DOWN, ref, :process, pid, reason}, state) do
    case _get(state.ref_table, ref) do
      {:ok, key} ->
        Logger.warn("Process #{inspect(pid)} went down: #{inspect(reason)}")
        :ets.delete(state.ref_table, ref)
        :ets.delete(state.pid_table, key)
    end

    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}
end
