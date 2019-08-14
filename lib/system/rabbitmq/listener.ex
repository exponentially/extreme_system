defmodule Extreme.System.RabbitMQ.Listener do
  alias Extreme.System.RabbitMQ.ChannelManager
  use GenServer
  use AMQP
  require Logger

  ### Client API

  def start_link(channel_manager, listener_name, definition, opts) when is_map(definition),
    do: GenServer.start_link(__MODULE__, {channel_manager, listener_name, definition}, opts)

  ### Server Callbacks

  def init({channel_manager, listener_name, definition}) do
    chan = ChannelManager.get_channel(channel_manager, listener_name)
    :ok = _set_queue(chan, definition)
    {:ok, consumer_tag} = Basic.consume(chan, definition.queue.name)

    {:ok,
     %{
       channel: chan,
       consumer_tag: consumer_tag,
       processor: definition.event_processor,
       status: :receiving
     }}
  end

  defp _set_queue(chan, definition) do
    q = definition.queue
    q_name = q.name

    if q[:qos_opts],
      do: :ok = Basic.qos(chan, q.qos_opts)

    if q[:declare_opts],
      do: {:ok, %{queue: ^q_name}} = Queue.declare(chan, q.name, q.declare_opts)

    if x = definition[:exchange] do
      if x[:options],
        do: :ok = Exchange.declare(chan, x.name, x.type, x.options)

      if q[:bind_opts],
        do: :ok = Queue.bind(chan, q.name, x.name, q.bind_opts)
    end

    Logger.info("Connected to #{q_name} queue")
  end

  # Confirmation sent by the broker after registering this process as a consumer
  def handle_info({:basic_consume_ok, %{consumer_tag: consumer_tag}}, state) do
    Logger.info("Successfully registered receiver with tag: #{consumer_tag}")
    {:noreply, state}
  end

  # Sent by the broker when the consumer is unexpectedly cancelled (such as after a queue deletion)
  def handle_info({:basic_cancel, %{consumer_tag: consumer_tag}}, state) do
    Logger.error("Receiver has been unexpectedly cancelled with tag: #{consumer_tag}")
    {:stop, :normal, state}
  end

  # Confirmation sent by the broker to the consumer process after a Basic.cancel
  def handle_info({:basic_cancel_ok, %{consumer_tag: consumer_tag}}, state) do
    Logger.info("Basic cancel successfull: #{consumer_tag}")
    {:noreply, state}
  end

  def handle_info(
        {:basic_deliver, body,
         %{delivery_tag: tag, routing_key: route, redelivered: redelivered?} = opts},
        state
      ) do
    consume(route, state.channel, tag, body, opts[:headers], state.processor, redelivered?)
    {:noreply, state}
  end

  def handle_info(_, state), do: {:noreply, state}

  defp consume(route, channel, tag, body, headers, event_processor, redelivered?) do
    ack = fn -> Basic.ack(channel, tag, []) end
    nack = fn -> Basic.reject(channel, tag, requeue: false) end
    retry = fn -> Basic.reject(channel, tag, requeue: true) end

    headers =
      if is_list(headers) do
        Enum.reduce(headers, %{}, fn {k, _, v}, acc -> Map.put(acc, String.to_atom(k), v) end)
      else
        %{}
      end

    _consume(route, body, headers, redelivered?, ack, nack, retry, event_processor)
  end

  defp _consume(route, payload, headers, redelivered?, ack, nack, retry, event_processor) do
    Logger.metadata(headers)

    case event_processor.process(route, payload,
           redelivered?: redelivered?,
           ack: ack,
           nack: nack,
           retry: retry,
           listener: self()
         ) do
      :ok ->
        Logger.debug(fn -> "Acking message" end)
        :ok = ack.()

      {:error, :discard_message} ->
        Logger.debug(fn -> "Nacking message" end)
        :ok = nack.()

      :accepted ->
        Logger.debug(fn -> "Processor will ack/nack message. We have to move on..." end)

      _ ->
        Logger.debug(fn -> "Returning message for redelivery" end)
        :ok = retry.()
    end

    Logger.metadata([])
  end
end
