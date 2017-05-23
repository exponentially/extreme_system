defmodule Extreme.System.Application do
  defmacro __using__(_) do
    quote do
      use     Application
      require Logger
      import  Supervisor.Spec, warn: false
      alias   Extreme.System.NodeMonitor

      def start(type, _args) do
        Logger.info "Starting #{inspect __MODULE__} in #{inspect type} mode"
        nodes = Application.get_env(:extreme_system, :nodes)
        result = case connect_to_nodes(nodes) do
          :ok    -> _start()
          :error -> {:error, :cant_connect_to_cluster}
        end
        case result do
          {:ok, pid} when is_pid(pid) -> {:ok, pid}
          {:ok, opts} ->
            children = opts[:children]
            opts     = [strategy: :one_for_one, name: opts[:name]]
            Supervisor.start_link(children ++ support_children(), opts)
          other -> other
        end
      end

      defp connect_to_nodes(nodes) do
        Logger.info "Trying to connect node #{inspect Node.self} to: #{inspect nodes}"
        nodes
        |> Enum.map(&System.get_env/1)
        |> Enum.reject(&is_nil/1)
        |> Enum.map(&String.to_atom/1)
        |> Enum.each(&Node.connect/1)
        spawn fn ->
          :timer.sleep 1000
          Logger.info "Connected nodes: #{inspect Node.list}"
        end
        if Enum.count(Node.list) > 0, do: :ok, else: :error
      end

      defp support_children,
        do: [ worker(NodeMonitor, []) ]
    end
  end
end
