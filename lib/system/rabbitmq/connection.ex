defmodule Extreme.System.RabbitMQ.Connection do
  use GenServer
  use AMQP
  require Logger

  ### Client API

  @doc """
  Starts the RabbitMQ connection.
  """
  def start_link(bus_settings, opts),
    do: GenServer.start_link(__MODULE__, bus_settings, opts)

  def get_connection(server),
    do: GenServer.call(server, :get_connection)

  ### Server Callbacks

  def init(bus_settings),
    do: connect_to_rabbit(bus_settings, 1)

  def handle_call(:get_connection, _from, conn),
    do: {:reply, conn, conn}

  defp connect_to_rabbit(_bus_settings, 4), do: {:error, :cannot_connect}

  defp connect_to_rabbit(bus_settings, tries) do
    Logger.info("Connecting to RabbitMQ...")
    Logger.debug(inspect(bus_settings))

    case Connection.open(bus_settings) do
      {:ok, conn} ->
        Process.link(conn.pid)
        {:ok, conn}

      _e ->
        Logger.warn(
          "Publisher connection unsuccessfull. Will have #{tries + 1}. retry in a second"
        )

        :timer.sleep(1000)
        connect_to_rabbit(bus_settings, tries + 1)
    end
  end

  # Confirmation sent by the broker after registering this process as a consumer
  def handle_info({:basic_consume_ok, %{consumer_tag: consumer_tag}}, chan) do
    Logger.info("Successfully registered publisher with tag: #{consumer_tag}")
    {:noreply, chan}
  end

  # Sent by the broker when the consumer is unexpectedly cancelled (such as after a queue deletion)
  def handle_info({:basic_cancel, %{consumer_tag: consumer_tag}}, chan) do
    Logger.error("Publisher has been unexpectedly cancelled with tag: #{consumer_tag}")
    {:stop, :normal, chan}
  end

  # Confirmation sent by the broker to the consumer process after a Basic.cancel
  def handle_info({:basic_cancel_ok, %{consumer_tag: consumer_tag}}, chan) do
    Logger.info("Basic cancel successfull: #{consumer_tag}")
    {:noreply, chan}
  end
end
