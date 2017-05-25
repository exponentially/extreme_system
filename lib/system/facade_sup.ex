defmodule Extreme.System.FacadeSup do
  use Supervisor

  def start_link(facade_module, facade_name), 
    do: Supervisor.start_link __MODULE__, {facade_module, facade_name}, name: name(facade_name)

  def init({facade_module, facade_name}) do
    children = [
      supervisor( Task.Supervisor, [[name: request_sup_name(facade_name)]]),
      worker(     facade_module,   [request_sup_name(facade_name), [name: facade_name]]),
    ]
    supervise children, strategy: :one_for_one
  end


  defp name({:global, facade_name}),
    do: name(facade_name)
  defp name(facade_name),
    do: "#{facade_name |> to_string()}.Supervisor" |> String.to_atom

  defp request_sup_name({:global, facade_name}),
    do: request_sup_name(facade_name)
  defp request_sup_name(facade_name),
    do: "#{facade_name |> to_string()}.RequestHandler" |> String.to_atom
end
