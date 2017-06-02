defmodule Extreme.System.AggregateGroup do
  use     Supervisor
  alias   Extreme.System.{AggregatePidFacade, AggregatePidManager}

  def start_link(prefix, aggregate_mod),
    do: Supervisor.start_link __MODULE__, {prefix, aggregate_mod}, name: name(aggregate_mod)

  def init({prefix, aggregate_mod}) do
    children = [
      supervisor( AggregatePidManager, [prefix, aggregate_mod]),
      worker(     AggregatePidFacade,  [prefix, aggregate_mod])
    ]
    supervise children, strategy: :one_for_one
  end

  def name(aggregate_mod), do: "#{aggregate_mod}.Group" |> String.to_atom
end
