defmodule Extreme.System.RabbitMQ.Consumers do
  use Supervisor

  def start_link(connection_name, configuration, opts),
    do: Supervisor.start_link(__MODULE__, {connection_name, configuration}, opts)

  def init({connection_name, configuration}) do
    conn = Extreme.System.RabbitMQ.Connection.get_connection connection_name
    children = configuration
                |> Enum.map(&define_worker(conn, &1))

    supervise children, strategy: :one_for_one
  end

  defp define_worker(conn, {:publisher, name, targets}),
    do: worker( Extreme.System.RabbitMQ.Publisher, [conn, targets,    [name: name]], id: name)

  defp define_worker(conn, {:listener,  name, definition}),
    do: worker( Extreme.System.RabbitMQ.Listener,  [conn, definition, [name: name]], id: name)
end
