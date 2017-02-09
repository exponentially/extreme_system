defmodule Extreme.System.PidRegistry do
  @moduledoc """
  Keeps track of registered pids.
  """

  require Logger
  use GenServer

  ## Client API

  @doc """
  Starts process registry
  """
  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, :ok, opts)

  @doc """
  Returns `true` if `key` is already registered in `server`, `false` otherwise.
  """
  def has_key?(server, key), do: GenServer.call(server, {:has_key?, key})

  @doc """
  Looks up the process pid for `id` stored in `server`.

  Returns `{:ok, pid}` if the one exists, `:error` otherwise.
  """
  def get(server, id), do: GenServer.call(server, {:get, id})

  @doc """
  Ensures there is a `pid` associated with `key` in `server`.

  Returns :ok once when process is successfully registered
  """
  def register(server, key, pid), do: GenServer.call(server, {:register, key, pid})


  ## Server Callbacks

  def init(:ok), do: {:ok, %{processes: %{}, refs: %{}}}

  def handle_call({:has_key?, key}, _from, state) do
    {:reply, Map.has_key?(state.processes, key), state}
  end

  def handle_call({:get, key}, _from, state) do
    {:reply, Map.fetch(state.processes, key), state}
  end

  def handle_call({:register, key, pid}, _from, state) do
    state = unless Map.has_key?(state.processes, key) do
      ref   = Process.monitor pid
      state = put_in state.refs[ref], key
      put_in state.processes[key], pid
    else
      state
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
