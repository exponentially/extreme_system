defmodule Extreme.System.RabbitMQ.Publisher do
  alias   Extreme.System.RabbitMQ.ChannelManager
  use     GenServer
  use     AMQP
  require Logger

  ## Client API

  def start_link(channel_manager, publisher_name, targets, opts) when is_list(targets),
    do: GenServer.start_link __MODULE__, {channel_manager, publisher_name, targets}, opts

  def publish(server, command, metadata \\ [])
  def publish(server, {:exchange, name, route, payload}, metadata),
    do: GenServer.call(server, {:publish, :exchange, name, route, payload, metadata})
  def publish(server, {:queue, name, payload}, metadata),
    do: GenServer.call(server, {:publish, :queue, name, payload, metadata})


  ## Server Callbacks

  def init({channel_manager, publisher_name, targets}) do
    targets = targets
              |> Enum.map(&declare(channel_manager, publisher_name, &1))
              |> Enum.into(%{})
    Logger.info fn -> "Declared push targets: #{targets |> Map.keys |> Enum.join(", ")}" end
    {:ok, %{targets: targets}}
  end

  def handle_call({:publish, :exchange, name, route, payload, metadata}, _from, state) do
    {:ok, chan} = case state.targets["exchange:" <> name] do
      nil  -> {:error, "Exchange #{name} is not registered with this publisher"}
      chan -> {:ok, chan}
    end
    response = _publish route, payload, metadata, chan, name
    {:reply, response, state}
  end
  def handle_call({:publish, :queue, name, payload, metadata}, _from, state) do
    {:ok, chan} = case state.targets["queue:" <> name] do
      nil  -> {:error, "Queue #{name} is not registered with this publisher"}
      chan -> {:ok, chan}
    end
    response = _publish name, payload, metadata, chan
    {:reply, response, state}
  end

  defp declare(channel_manager, publisher_name, {:exchange, %{name: name}=definition}) do
    chan        = ChannelManager.get_channel channel_manager, publisher_name, "exchange:#{name}"
    if definition[:options],
      do: :ok   = Exchange.declare chan, name, definition.type, definition.options
    {"exchange:" <> name, chan}
  end
  defp declare(channel_manager, publisher_name, {:queue, %{name: name}=definition}) do
    chan                          = ChannelManager.get_channel channel_manager, publisher_name, "queue:#{name}"
    if definition[:options],
      do: {:ok, %{queue: ^name}}  = Queue.declare chan, name, definition.options
    {"queue:" <> name, chan}
  end

  defp _publish(route, command, metadata, chan, exchange \\ "") do
    metadata = Enum.into metadata, []
    Logger.metadata metadata
    Logger.info  fn -> "Publishing to #{exchange} exchange on route #{route}" end
    Logger.debug fn -> inspect command end
    :ok = Basic.publish chan, exchange, route, command, headers: metadata
    Logger.metadata []
  end
end
