defmodule Extreme.System.EventStore do
  use     GenServer
  require Logger
  alias   Extreme.Msg, as: ExMsg

  def name(prefix), do: "#{prefix |> to_string()}.EventStore" |> String.to_atom

  @doc """
  Starts the ES connection.
  """
  def start_link(config_module, extreme, opts), 
    do: GenServer.start_link __MODULE__, {config_module, extreme}, opts

  def has?(server, aggregate, id), 
    do: GenServer.call(server, {:has?, aggregate, id})

  def save_events(server, identifier, events, metadata \\ %{}, expected_version \\ -2)
  def save_events(_, _, [], _, expected_version),
    do: {:ok, expected_version}
  def save_events(server, {_aggregate, _id}=identifier, events, metadata, expected_version),
    do: GenServer.call server, {:save_events, {identifier, events, metadata, expected_version}}

  def stream_events(server, {_aggregate, _id}=identifier, starting_event \\ 0, per_page \\ 4096),
    do: GenServer.call server, {:stream_events, identifier, starting_event, per_page}


  ## Server Callbacks

  def init({config_module, extreme}), 
    do: {:ok, %{config: config_module, extreme: extreme}}


  defp stream_name(config_mod, {aggregate, id}) do
    name = Keyword.fetch! config_mod.stream_for, aggregate
    "#{name}-#{id}"
  end

  def handle_call({:has?, aggregate, id}, _from, state) do
    stream = stream_name state.config, {aggregate, id}
    case Extreme.execute(state.extreme, read_events(stream, 0, 1)) do
      {:ok, _response} -> {:reply, true, state}
      _ -> {:reply, false, state}
    end
  end

  def handle_call({:save_events, {identifier, events, metadata, expected_version}}, _from, state) do
    stream = stream_name state.config, identifier
    case Extreme.execute state.extreme, write_events(stream, events, metadata, expected_version) do
      {:ok, result} -> 
        {:reply, {:ok, result.last_event_number}, state}
      {:error, :WrongExpectedVersion, _} -> 
        {:reply, {:error, :wrong_expected_version, expected_version}, state}
      other ->
        {:reply, {:error, other}, state}
    end
  end

  def handle_call({:stream_events, identifier, start_version, per_page}, _from, state) do
    stream = stream_name state.config, identifier
    events = get_stream_events state.extreme, stream, start_version, per_page
    {:reply, events, state}
  end
         
  defp get_stream_events(extreme, stream, start_at, per_page) do
    Stream.resource(
      fn -> fetch_stream_events({extreme, stream, start_at, per_page, false}) end,
      &return_stream_events/1,
      fn x -> x end
    )
  end

  defp fetch_stream_events({extreme, stream, start_at, per_page, _is_completed}) do
    Logger.debug "Taking #{per_page} items starting from #{start_at} for stream: #{inspect stream}"
    {events, is_end_of_stream} = case Extreme.execute(extreme, read_events(stream, start_at, per_page)) do
      {:ok, response} ->
      events = Enum.map(response.events, fn e ->
        event = Poison.decode!(e.event.data, as: struct(String.to_atom(e.event.event_type)), keys: :atoms)
        {event, e.event.event_number}
      end)
      {events, response.is_end_of_stream}
      {:error, :NoStream, _} -> {[], true}
    end
    {events, {extreme, stream, start_at + per_page, per_page, is_end_of_stream}}
  end

  defp return_stream_events({[], {_, _, _, _, is_completed} = params}) when is_completed, 
  do: {:halt, params}
  defp return_stream_events({[], params}) do
    {result, next} = fetch_stream_events params
    {result, {[], next}}
  end
  defp return_stream_events({events, params}), 
  do: {events, {[], params}}
  
  defp write_events(stream, events, metadata, expected_version) when is_list(metadata),
    do: write_events stream, events, Enum.into(metadata, %{}), expected_version
  defp write_events(stream, events, metadata, expected_version) do
    metadata = (metadata || %{})
                |> Map.put(:emitted_at, DateTime.utc_now |> DateTime.to_iso8601)
    proto_events = Enum.map(events, fn event ->
       ExMsg.NewEvent.new(
         event_id: Extreme.Tools.gen_uuid(),
         event_type: to_string(event.__struct__),
         data_content_type: 1,
         metadata_content_type: 1,
         data: Poison.encode!(event),
         metadata: Poison.encode!(metadata)
       ) end)
     ExMsg.WriteEvents.new(
       event_stream_id: stream,
       expected_version: expected_version,
       events: proto_events,
       require_master: false
     )
   end
   
   defp read_events(stream, start_at, per_page) do
     ExMsg.ReadStreamEvents.new(
     event_stream_id: stream,
     from_event_number: start_at,
     max_count: per_page,
     resolve_link_tos: true,
     require_master: false
     )
   end
     #
     #      defoverridable [stream_name: 1]
end
