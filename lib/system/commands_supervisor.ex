defmodule Extreme.System.CommandsSupervisor do
  defmacro __using__(opts) do
    quote do

      use     Supervisor
      require Logger

      @prefix Keyword.fetch!(unquote(opts), :prefix) |> to_string


      def start_link(extreme_settings) do
        name = String.to_atom(@prefix <> ".CommandsSupervisor")
        Supervisor.start_link(__MODULE__, {extreme_settings}, name: name)
      end

      def init({extreme_settings}) do
        extreme_name = String.to_atom(@prefix <> ".ExtremeWrite")

        groups = unquote(opts)
                 |> Keyword.fetch!(:streams)
                 |> Enum.map(fn {aggregate, stream} ->
                      supervisor( Extreme.System.AggregateGroup, [aggregate, aggregate], id: aggregate)
                    end)
        children = [
          worker(     Extreme,                            [extreme_settings, [name: extreme_name]], id: extreme_name),
          #worker(     Extreme.System.EventStore,          [extreme_name,     [name: es_name]]),
        ] ++ groups

        supervise children, strategy: :one_for_one
      end

    end
  end
end
