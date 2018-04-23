# Extreme.System

**TODO: Add description**

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed as:

  1. Add `extreme_system` to your list of dependencies in `mix.exs`:

    ```elixir
    def deps do
      [{:extreme_system, "~> 0.1.0"}]
    end
    ```

  2. Ensure `extreme_system` is started before your application:

    ```elixir
    def application do
      [applications: [:extreme_system]]
    end
    ```
## Version

This branch originated from `extreme_system` version `0.0.2`, which is on [Elixir 1.3](https://hexdocs.pm/elixir/1.3.4/).
It should be used for smaller improvements and bugfixes, while staying true Elixir version 1.3.

  1. Add this specific branch of `extreme_system` to your list of dependencies in `mix.exs`:
  
  	```elixir
  	def deps do
  	  [{:extreme_system, git: "https://github.com/exponentially/extreme_system.git", branch: "ex_1.3"}]
  	end
  	```
