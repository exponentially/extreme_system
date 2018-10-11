defmodule Extreme.System.RabbitMQ.ListenerMonitor do
  use GenServer
  require Logger

  @normal_shutdowns ~w(normal)a

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, :ok, opts)

  def init(:ok) do
    Logger.info fn -> "Starting listener monitor" end
    {:ok, %{}}
  end

  def monitor(server, listener, listener_name, retry) do
    GenServer.call(server, {:monitor, listener, listener_name, retry})
  end

  def handle_call({:monitor, listener, listener_name, retry}, _from, state)
  when  is_pid      (listener)
  and   is_function (retry) do
    Logger.debug fn -> "ListenerMonitor: monitoring #{inspect listener_name} (#{inspect listener})" end
    Process.monitor listener
    {:reply, :ok, Map.put(state, listener, {listener_name, retry})}
  end

  def handle_info({:DOWN, _ref, :process, pid, reason}, state) do
    {{listener_name, retry}, state} = Map.pop(state, pid)
    :ok = case reason do
      reason when reason in @normal_shutdowns  ->
        Logger.debug fn -> "ListenerMonitor: #{inspect listener_name} (#{inspect pid}) closed regularly - #{inspect reason}." end
        :ok
      other                                               ->
        Logger.warn fn -> "ListenerMonitor retrying #{inspect listener_name} (#{inspect pid}) - #{inspect other}" end
        retry.()
    end
    {:noreply, state}
  end
  def handle_info(_msg, state) do
    {:noreply, state}
  end
end
