defmodule Extreme.System.NodeMonitor do
  require Logger

  def start_link do
    {:ok, spawn_link fn -> 
      :global_group.monitor_nodes true
      Process.register self(), __MODULE__
      monitor()
    end}
  end

  def monitor do
    receive do
      {:nodeup, node}   -> Logger.info "NodeMonitor: #{node} joined"
      {:nodedown, node} -> 
        Logger.warn "NodeMonitor: #{node} left"
        check_cluster()
    end
    monitor()
  end

  defp check_cluster do
    unless in_cluster?(),
      do: Logger.error "There's no lighthouse in this cluster. We should restart!" # Node.stop
  end

  defp in_cluster?,
    do: Node.list |> Enum.any?(fn node -> node |> to_string |> String.starts_with?("lighthouse") end)
end
