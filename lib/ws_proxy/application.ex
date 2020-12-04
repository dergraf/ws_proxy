defmodule WsProxy.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    import Supervisor.Spec, warn: false

    children = [
      {Finch,
       name: WsProxy.WebhookPool,
       pools: %{
         default: [
           size: System.get_env("WSPROXY_WEBHOOK_POOL_SIZE", "100") |> String.to_integer()
         ]
       }},
      Plug.Adapters.Cowboy.child_spec(
        scheme: :http,
        plug: WsProxy.Router,
        options: [
          dispatch: dispatch(),
          port: System.get_env("WSPROXY_PORT", "4000") |> String.to_integer()
        ]
      )
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: WsProxy.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp dispatch do
    [
      {:_,
       [
         {:_, WsProxy.SocketHandler, []}
       ]}
    ]
  end
end
