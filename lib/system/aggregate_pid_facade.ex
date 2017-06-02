defmodule Extreme.System.AggregatePidFacade do
  use     GenServer
  require Logger
  alias   Extreme.System.{EventStore, AggregateSup}
  alias   Extreme.System.AggregateRegistry, as: Registry

  def name(aggregate_mod), do: "#{aggregate_mod}.PidFacade" |> String.to_atom

  ## Client API

  def start_link(prefix, aggregate_mod), 
    do: GenServer.start_link(__MODULE__, {prefix, aggregate_mod}, name: name(aggregate_mod))

  def get_pid(server, key),
    do: GenServer.call(server, {:get_pid, key})

  def spawn_new(server),
    do: GenServer.call(server, :spawn_new)


  def init({prefix, aggregate_mod}) do
    state = %{
      event_store:   EventStore.name(prefix),
      registry:      Registry.name(aggregate_mod),
      aggregate_sup: AggregateSup.name(aggregate_mod),
      aggregate_mod: aggregate_mod
    }
    {:ok, state}
  end

  def handle_call(:spawn_new, _from, state) do
    key = UUID.uuid1
    {:ok, pid} = AggregateSup.start_child state.aggregate_sup
    :ok        = Registry.register state.registry, key, pid
    {:reply, {:ok, pid, key}, state}
  end

  def handle_call({:get_pid, key}, _from, state),
    do: {:reply, _get_pid(key, state), state}


  defp _get_pid(key, state) do
    case Registry.get(state.registry, key) do
      :error     -> _get_from_es(state.event_store, state.aggregate_sup, state.registry, state.aggregate_mod, key)
      {:ok, pid} -> {:ok, pid}
    end
  end

  defp _get_from_es(event_store, aggregate_sup, registry, aggregate_mod, key) do
    case EventStore.has?(event_store, aggregate_mod, key) do
      true ->
        events = EventStore.stream_events event_store, {aggregate_mod, key}
        Logger.debug "Applying events for existing aggregate #{key}"
        {:ok, pid} = AggregateSup.start_child aggregate_sup
        :ok        = aggregate_mod.apply pid, events
        :ok        = Registry.register registry, key, pid
        {:ok, pid}
      false ->
        Logger.warn "No events found for carrier lane: #{key}"
        {:error, :not_found}
    end
  end
end
