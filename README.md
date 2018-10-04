# Extreme.System

## Aggregates

Aggregates are loaded into memory on demand, meaning that once command is dispatched to aggregate.

1. First, aggregates are created by using `Extreme.System.GenAggregate`. Here is an example of an aggregate:

```
defmodule ExtremeSystem.Example.Users.Aggregates.User do
  use     Extreme.System.GenAggregate
  alias   ExtremeSystem.Example.Events, as: Event
  import  Ecto.Changeset

  defmodule State, 
    do: defstruct GenAggregate.state_params ++ 
        [:id, :name]


  ## Client API

  def start_link(ttl \\ 2_000, opts \\ []),
    do: GenAggregate.start_link(__MODULE__, ttl, opts)

  def new(server, id, cmd),
    do: exec(server, {:new, id, cmd})

  def update_profile(server, cmd),
    do: exec(server, {:update_profile, cmd})


  ## Server Callbacks

  def init(ttl),
    do: {:ok, struct(State, initial_state(ttl))}

  ### Command handling

  def handle_exec({:new, id, cmd}, from, state) do
    events = [
      %Event.User.Created{id: id, email: cmd["email"]},
      %Event.User.ProfileSet{id: id, name: cmd["name"]}
    ]
    {:block, from, {:events, events}, state}
  end

  def handle_exec({_cmd, %{"id" => id, "version" => expected_version}}, from, %{id: id, version: current_version}=state) when expected_version != current_version,
    do: {:noblock, from, {:error, :wrong_expected_version, current_version, expected_version}, state}

  def handle_exec({:update_profile, %{"id" => id, "name" => name}}, from, %{id: id, name: name}=state),
    do: {:noblock, from, {:ok, state.version}, state}
  def handle_exec({:update_profile, %{"id" => id}=cmd}, from, %{id: id}=state) do
    case _update_profile(cmd, state) do
      {:ok, events} -> {:block,   from, {:events, events}, state}
      other         -> {:noblock, from, other,             state}
    end
  end

  def handle_exec({cmd, payload}, from, state),
    do: {:noblock, from, {:error, :conflict, "Can't execute #{inspect cmd} with: #{inspect payload}"}, state}

  defp _update_profile(cmd, state) do
    case _validate_profile_update(cmd) do
      %{valid?: false}=changeset -> {:error, changeset}
      %{changes: data} ->
        events = [
          %Event.User.ProfileSet{id: state.id, name: data.name}
        ]
        {:ok, events}
    end
  end

  defp _validate_profile_update(cmd) do
    blank = %{}
    types = %{name: :string}
    {blank, types}
      |> cast(cmd, Map.keys(types))
      |> validate_required([:name])
      |> validate_length(:name, min: 6)
  end

  ### Apply events

  defp apply_event(%Event.User.Created{}=event, state) do
    %State{state| 
      id: event.id
    }
  end
  defp apply_event(%Event.User.ProfileSet{}=event, state) do
    %State{state| 
      name: event.name
    }
  end
  defp apply_event(_, state), do: state
end
```

2. Next, we need to register aggregates with a scheduler. We make use of `Extreme.System.CommandConfiguration`:

```
defmodule ExtremeSystem.Example.Users.CommandConfiguration do
  alias   ExtremeSystem.Example.Users.Aggregates
  use     Extreme.System.CommandConfiguration, aggregates: [{Aggregates.User,    "ex_users"},
                                                            {Aggregates.Company, "ex_company"}]
end
```

3. Next we need to create a message handler, that will dispatch commands to appropriate aggregates. For this we use `Extreme.System.MessageHandler`. To sent a message to an existing aggregate use `with_aggregate`, while to send a message to a new aggregate (e.g. creation) we use `with_new_aggregate`. The latter assumes there is at least one event persisted in EventStore that is related to your aggregate otherwise you will receive an error:

```
defmodule ExtremeSystem.Example.MessageHandlers.Users do
  alias   ExtremeSystem.Example.Users,   as: App
  use     Extreme.System.MessageHandler, prefix:        App,
                                         aggregate_mod: App.Aggregates.User
  import  ExtremeSystem.Example.MessageHandlers.ResponseHelper, only: [respond_on: 1]

  def new(cmd) do
    with_new_aggregate("Registering new user", cmd, fn {:ok, pid, id} -> 
      aggregate_mod().new(pid, id, cmd)
    end) |> respond_on
  end

  def update_profile(%{"id" => id}=cmd) do
    with_aggregate("Updating profile for user #{inspect id}", id, fn {:ok, pid} ->
      aggregate_mod().update_profile(pid, cmd)
    end) |> respond_on
  end
end
```

4. To route a message to appropriate message handler, we need to use `Extreme.System.Facade`:

```
defmodule ExtremeSystem.Example.Users.Facade do
  use     Extreme.System.Facade, default_cache: 1_000

  alias   ExtremeSystem.Example.MessageHandlers, as: MsgHandler

  route   :new,            MsgHandler.Users
  route   :update_profile, MsgHandler.Users
end
```

5. We can then register this facade globally:

```
defmodule ExtremeSystem.Example.Users do
  alias   ExtremeSystem.Example.Users, as: App
  alias   Extreme.System,              as: ExSys
  use     ExSys.Application

  def _start do
    import Supervisor.Spec, warn: false

    extreme_settings = Application.get_env(:users, :extreme)

    children = [
      supervisor( ExSys.CommandSup, [App.CommandConfiguration, App, extreme_settings]),
      supervisor( ExSys.FacadeSup,  [App.Facade, {:global, Example.UsersFacade}]),
    ]

    {:ok, children: children, name: __MODULE__}
  end
end
```

6. And then call when we need it:

```
res = :global.whereis_name(facade)
GenServer.call(res, command, timeout: 2_000)
```


## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed as:

  1. Add `extreme_system` to your list of dependencies in `mix.exs`:

    ```elixir
    def deps do
      [{:extreme_system, "~> 0.2.14"}]
    end
    ```

## Example

An example system that uses `Extreme.System` can be found here: https://github.com/exponentially/extreme_system_example
