defmodule Extreme.System.RabbitMQ.Supervisor do
  use Supervisor

  @moduledoc """
  Configuration examples:


    [
      {:publisher, MyApp.Rabbit.ExchangePublisher, [
         {:exchange, %{
                        name:    "exchange_name",
                        type:    :topic,
                        options: [durable: true]
                      }}
      ]},
      {:publisher, MyApp.Rabbit.QueuePublisher, [
         {:queue,    %{
                        name:    "queue_name_to_publish",
                        options: [
                                   durable:   true,
                                   arguments: [{"x-dead-letter-exchange",    :longstr, "dead"}, 
                                               {"x-dead-letter-routing-key", :longstr, "dead.my_app.queue_name_to_publish"}]
                                 ]
                      }}
      ]},
      {:listener, MyApp.Rabbit.SomeQueueListener, %{
         event_processor: MyApp.SomeQueueProcessor,
         exchange: %{
           name:    "exchange_name",
           type:    :topic,
           options: [durable: true]
         },
         queue: %{
           name:         "some_queue_listener",
           qos_opts:     [prefetch_count: 100],
           declare_opts: [
             exclusive: false, 
             durable: true, 
             arguments: [
               {"x-dead-letter-exchange", :longstr, "dead"}, 
               {"x-dead-letter-routing-key", :longstr, "dead.my_app.some_queue_listener"}
             ]
           ],
           bind_opts: [routing_key: "#"],
         }
      }}
    ]

  Minimal required configuration (when exchanges and queues are declared somewhere else) is:

    [
      {:publisher, MyApp.Rabbit.ExchangePublisher, [
         {:exchange, %{ name: "exchange_name" }}
      ]},
      {:publisher, MyApp.Rabbit.QueuePublisher, [
         {:queue,    %{ name: "queue_name_to_publish" }}
      ]},
      {:listener,  MyApp.Rabbit.SomeQueueListener, %{
         event_processor: MyApp.SomeQueueProcessor,
         exchange:        %{ name: "exchange_name" },
         queue:           %{ name: "some_queue_listener" }
      }}
    ]

  When listener receives message it calls event_processor.process(route, payload, [redelivered?: redelivered?]=options)
  function. If it returns :ok, messages is acked. On {:error, :discard_message} message is nacked. On anything else
  message is returned for redelivery.
  """

  def start_link(prefix, bus_settings, configuration) do
    prefix = to_string(prefix) <> ".RabbitMQ"
    name   = String.to_atom(prefix <> ".Supervisor")
    Supervisor.start_link(__MODULE__, {prefix, bus_settings, configuration}, name: name)
  end

  def init({prefix, bus_settings, configuration}) do
    connection_name   = String.to_atom(prefix <> ".Connection")
    channel_manager   = String.to_atom(prefix <> ".ChannelManager")
    listener_monitor  = String.to_atom(prefix <> ".ListenerMonitor")
    consumers_name    = String.to_atom(prefix <> ".Consumers")
    children = [
      worker(     Extreme.System.RabbitMQ.Connection,       [bus_settings,                                      [name: connection_name]]),
      worker(     Extreme.System.RabbitMQ.ChannelManager,   [connection_name,                                   [name: channel_manager]]),
      worker(     Extreme.System.RabbitMQ.ListenerMonitor,  [                                                   [name: listener_monitor]]),
      supervisor( Extreme.System.RabbitMQ.Consumers,        [channel_manager, listener_monitor, configuration,  [name: consumers_name]]),
    ]

    supervise children, strategy: :rest_for_one
  end
end
