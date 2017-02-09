defmodule Extreme.System.AggregateSup do
  use     Supervisor

  def start_link(aggregate_module, opts), 
    do: Supervisor.start_link(__MODULE__, aggregate_module, opts)

  def start_child(sup_name, child_params \\ []), 
    do: Supervisor.start_child(sup_name, child_params)

  def init(aggregate_module) do
    children = [ worker(aggregate_module, [], restart: :temporary) ]
    supervise children, strategy: :simple_one_for_one
  end
end
