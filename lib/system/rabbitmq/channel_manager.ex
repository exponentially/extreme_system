defmodule Extreme.System.RabbitMQ.ChannelManager do
  use GenServer
  alias AMQP.Channel
  require Logger

  ### Client API

  @doc """
  Starts the RabbitMQ connection.
  """
  def start_link(connection_name, opts),
    do: GenServer.start_link(__MODULE__, connection_name, opts)

  def get_channel(server, listener),
    do: GenServer.call(server, {:get_channel, listener})

  def get_channel(server, publisher, target),
    do: GenServer.call(server, {:get_channel, publisher, target})

  ### Server Callbacks

  def init(connection_name) do
    conn = Extreme.System.RabbitMQ.Connection.get_connection(connection_name)
    Process.link(conn.pid)
    {:ok, %{connection: conn, channel_mappings: %{listeners: %{}, publishers: %{}}}}
  end

  def handle_call(
        {:get_channel, listener},
        _from,
        %{connection: conn, channel_mappings: %{listeners: mappings}} = state
      ) do
    new_mappings = _add_channel_mapping(conn, listener, mappings)
    chan = new_mappings |> Map.get(listener)

    {:reply, chan, put_in(state[:channel_mappings][:listeners], new_mappings)}
  end

  def handle_call(
        {:get_channel, publisher, target},
        _from,
        %{connection: conn, channel_mappings: %{publishers: mappings}} = state
      ) do
    new_mappings = _add_channel_mapping(conn, publisher, target, mappings)
    chan = new_mappings |> get_in([publisher, target])

    {:reply, chan, put_in(state[:channel_mappings][:publishers], new_mappings)}
  end

  def handle_call(:get_state, _from, state),
    do: {:reply, state, state}

  defp _add_channel_mapping(conn, listener, mappings) do
    Map.put_new_lazy(mappings, listener, fn -> _create_channel(conn) end)
  end

  defp _add_channel_mapping(conn, publisher, target, mappings) do
    case get_in(mappings, [publisher, target]) do
      nil ->
        publisher_map =
          mappings
          |> Map.get(publisher, %{})
          |> Map.put(target, _create_channel(conn))

        mappings |> Map.put(publisher, publisher_map)

      _ ->
        mappings
    end
  end

  defp _create_channel(conn) do
    {:ok, chan} = Channel.open(conn)
    chan
  end
end
