defmodule Extreme.System.AggregateGroup do
  use     Supervisor
  alias   Extreme.System.AggregateSup
  alias   Extreme.System.PidRegistry

  def start_link(group_name, aggregate_module) do
    name = "#{group_name}.AggregateGroup" |> String.to_atom
    Supervisor.start_link __MODULE__, {group_name, aggregate_module}, name: name
  end

  def spawn_new(group_name, key, child_params \\ []) do
    {:ok, pid} = group_name |> sup_name      |> AggregateSup.start_child(child_params)
    :ok        = group_name |> registry_name |> PidRegistry.register(key, pid)
    {:ok, pid}
  end

  def get_registered(group_name, key),
    do: group_name |> registry_name |> PidRegistry.get(key)


  def init({group_name, aggregate_module}) do
    children = [
      supervisor( AggregateSup, [aggregate_module, [name: sup_name(group_name)]]),
      worker(     PidRegistry,  [[name: registry_name(group_name)]])
    ]
    supervise children, strategy: :one_for_all
  end


  defp sup_name(group_name),      do: "#{group_name}.AggregateSup"      |> String.to_atom
  defp registry_name(group_name), do: "#{group_name}.AggregateRegistry" |> String.to_atom
end
