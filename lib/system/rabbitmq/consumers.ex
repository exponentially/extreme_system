defmodule Extreme.System.RabbitMQ.Consumers do
  use Supervisor

  def start_link(channel_manager, listener_monitor, configuration, opts),
    do: Supervisor.start_link(__MODULE__, {channel_manager, listener_monitor, configuration}, opts)

  def init({channel_manager, listener_monitor, configuration}) do
    children = configuration
                |> Enum.map(&define_worker(channel_manager, listener_monitor, &1))

    supervise children, strategy: :one_for_one
  end

  defp define_worker(channel_manager, _, {:publisher, name, targets}),
    do: worker( Extreme.System.RabbitMQ.Publisher, [channel_manager, name, targets,    [name: name]], id: name)

  defp define_worker(channel_manager, listener_monitor, {:listener,  name, definition}),
    do: worker( Extreme.System.RabbitMQ.Listener,  [channel_manager, listener_monitor, name, definition, [name: name]], id: name)
end
