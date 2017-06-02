defmodule Extreme.System.CommandConfiguration do
  defmacro __using__(opts) do
    quote do
      use     Supervisor
      require Logger
      
      def stream_for(), do: unquote(opts[:aggregates])

      def start_link(prefix),
        do: Supervisor.start_link __MODULE__, prefix, name: Extreme.System.CommandConfiguration.name(prefix)


      def init(prefix) do
        children = unquote(Keyword.fetch! opts, :aggregates) 
                    |> Enum.map(fn item -> aggregate_group(item, prefix) end)
        supervise children, strategy: :one_for_one
      end

      defp aggregate_group({aggr_mod, _stream}, prefix) do
        name = Extreme.System.AggregateGroup.name(aggr_mod)
        supervisor(Extreme.System.AggregateGroup, [prefix, aggr_mod], id: name)
      end
    end
  end

  def name(prefix),
    do: "#{prefix |> to_string()}.CommandConfiguration" |> String.to_atom
end
