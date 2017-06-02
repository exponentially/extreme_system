defmodule Extreme.System.CommandSup do
  use     Supervisor
  alias   Extreme.System, as: ExSys

  def start_link(configuration_module, prefix, extreme_settings), 
    do: Supervisor.start_link __MODULE__, {configuration_module, prefix, extreme_settings}, name: name(prefix)

  def init({configuration_module, prefix, extreme_settings}) do
    children = [
      supervisor( configuration_module, [prefix]),
      worker(     Extreme,              [extreme_settings,                           [name: extreme_name(prefix)]]),
      worker(     ExSys.EventStore,     [configuration_module, extreme_name(prefix), [name: ExSys.EventStore.name(prefix)]]),
    ]
    supervise children, strategy: :one_for_one
  end


  defp name(prefix),
    do: "#{prefix |> to_string()}.CommandSup" |> String.to_atom

  defp extreme_name(prefix),
    do: "#{prefix |> to_string()}.Extreme" |> String.to_atom
end
