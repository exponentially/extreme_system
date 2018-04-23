defmodule Extreme.System.RabbitMQ.Consumers do
  use Supervisor

  def start_link(channel_manager, configuration, opts),
    do: Supervisor.start_link(__MODULE__, {channel_manager, configuration}, opts)

  def init({channel_manager, configuration}) do
    children = configuration
                |> Enum.map(&define_worker(channel_manager, &1))

    supervise children, strategy: :one_for_one
  end

  defp define_worker(channel_manager, {:publisher, name, targets}),
    do: worker( Extreme.System.RabbitMQ.Publisher, [channel_manager, name, targets,    [name: name]], id: name)

  defp define_worker(channel_manager, {:listener,  name, definition}),
    do: worker( Extreme.System.RabbitMQ.Listener,  [channel_manager, name, definition, [name: name]], id: name)
end
