defmodule Extreme.System.AggregateGroup do
  use     Supervisor
  alias   Extreme.System.AggregateSup
  alias   Extreme.System.PidRegistry

  def start_link(group, aggregate_module),
    do: Supervisor.start_link __MODULE__, {group, aggregate_module}, name: group_name(group)

  def spawn_new(group, key, child_params \\ []) do
    {:ok, pid} = group |> sup_name      |> AggregateSup.start_child(child_params)
    :ok        = group |> registry_name |> PidRegistry.register(key, pid)
    {:ok, pid}
  end

  def get_registered(group, key),
    do: group |> registry_name |> PidRegistry.get(key)


  def init({group, aggregate_module}) do
    children = [
      supervisor( AggregateSup, [aggregate_module, [name: sup_name(group)]]),
      worker(     PidRegistry,  [[name: registry_name(group)]])
    ]
    supervise children, strategy: :one_for_all
  end


  defp group_name(group),    do: "#{group}Group"    |> String.to_atom
  defp sup_name(group),      do: "#{group}Sup"      |> String.to_atom
  defp registry_name(group), do: "#{group}Registry" |> String.to_atom
end
