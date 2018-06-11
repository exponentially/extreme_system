use Mix.Config

config :logger, :console,
  level: :debug,
  format: "$time [$level] $metadata$message\n",
  metadata: [:pid, :user]
