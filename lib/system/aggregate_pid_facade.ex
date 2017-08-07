defmodule Extreme.System.AggregatePidFacade do
  use     GenServer
  require Logger
  alias   Extreme.System.{EventStore, AggregateSup}
  alias   Extreme.System.AggregateRegistry, as: Registry

  def name(aggregate_mod), do: "#{aggregate_mod}.PidFacade" |> String.to_atom

  ## Client API

  def start_link(prefix, aggregate_mod), 
    do: GenServer.start_link(__MODULE__, {prefix, aggregate_mod}, name: name(aggregate_mod))

  def get_pid(server, key, when_not_registered),
    do: GenServer.call(server, {:get_pid, key, when_not_registered})

  def spawn_new(server, key),
    do: GenServer.call(server, {:spawn_new, key})

  def exit_process(server, key, reason),
    do: GenServer.cast(server, {:exit_process, key, reason})


  def init({prefix, aggregate_mod}) do
    state = %{
      event_store:   EventStore.name(prefix),
      registry:      Registry.name(aggregate_mod),
      aggregate_sup: AggregateSup.name(aggregate_mod),
      aggregate_mod: aggregate_mod
    }
    {:ok, state}
  end

  def handle_call({:spawn_new, key}, _from, state) do
    {:ok, pid} = AggregateSup.start_child state.aggregate_sup
    response = case Registry.register(state.registry, key, pid) do
      :ok   -> {:ok, pid}
      other -> other
    end
    {:reply, response, state}
  end

  def handle_call({:get_pid, key, when_not_registered}, _from, state),
    do: {:reply, _get_pid(key, state, when_not_registered), state}


  def handle_cast({:exit_process, key, reason}, state) do
    case Registry.get(state.registry, key) do
      {:ok, pid} -> 
        Logger.debug "Killing process #{inspect pid}: #{inspect reason}"
        AggregateSup.terminate_child state.aggregate_sup, pid
      _          -> :ok
    end
    {:noreply, state}
  end

  defp _get_pid(key, state, when_not_registered) do
    case Registry.get(state.registry, key) do
      :error     -> when_not_registered.(state.aggregate_mod, key)
      {:ok, pid} -> {:ok, pid}
    end
  end
end
