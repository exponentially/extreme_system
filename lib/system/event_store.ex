defmodule Extreme.System.EventStore do
  defmacro __using__(opts) do
    quote do
      use     GenServer
      require Logger
      alias   Extreme.Messages, as: ExMsg

      @doc """
      Starts the ES connection.
      """
      def start_link(extreme), 
        do: GenServer.start_link __MODULE__, extreme, name: process_name

      def has?({aggregate, id}), do:
        GenServer.call(process_name, {:has?, aggregate, id})

      def save_events(identifier, events, metadata \\ %{})
      def save_events(_, [], _), do: :ok
      def save_events({_aggregate, _id}=identifier, events, metadata),
        do: GenServer.call process_name, {:save_events, {identifier, events, metadata}}

      def stream_events({_aggregate, _id}=identifier, starting_event \\ 0),
        do: GenServer.call process_name, {:stream_events, identifier, starting_event}


      defp process_name, do: Keyword.fetch! unquote(opts), :process_name

      def stream_name({category, id}), do: "#{category}-#{id}"


      ## Server Callbacks

      def init(extreme), do: {:ok, %{extreme: extreme}}


      def handle_call({:has?, aggregate, id}, _from, state) do
        stream = stream_name {aggregate, id}
        case Extreme.execute(state.extreme, read_events(stream, 0, 1)) do
          {:ok, _response} -> {:reply, true, state}
          _ -> {:reply, false, state}
        end
      end
      def handle_call({:save_events, {{aggregate, id}, events, metadata}}, _from, state) do
        stream = stream_name {aggregate, id}
        {:ok, result} = Extreme.execute state.extreme, write_events(stream, events, metadata)
        {:reply, {:ok, result.last_event_number}, state}
      end
      def handle_call({:stream_events, {aggregate, id}, start_version}, _from, state) do
        stream = stream_name {aggregate, id}
        events = get_stream_events state.extreme, stream, start_version
        {:reply, events, state}
      end

      defp get_stream_events(extreme, stream, start_at, per_page \\ 4096) do
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
            event = Poison.decode!(e.event.data, as: struct(String.to_atom(e.event.event_type)))
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

      defp write_events(stream, events, metadata) when is_list(metadata),
        do: write_events stream, events, Enum.into(metadata, %{})
      defp write_events(stream, events, metadata) do
        proto_events = Enum.map(events, fn event ->
          ExMsg.NewEvent.new(
            event_id: Extreme.Tools.gen_uuid(),
            event_type: to_string(event.__struct__),
            data_content_type: 1,
            metadata_content_type: 1,
            data: Poison.encode!(event),
            metadata: Poison.encode!(metadata || %{})
          ) end)
        ExMsg.WriteEvents.new(
          event_stream_id: stream,
          expected_version: -2,
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

      defoverridable [stream_name: 1]
    end
  end
end
