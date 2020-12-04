defmodule WsProxy.SocketHandler do
  @behaviour :cowboy_websocket

  require Logger

  def init(req, _state) do
    headers = :cowboy_req.headers(req)
    path = :cowboy_req.path(req)
    querystring = :cowboy_req.qs(req)

    opts = %{
      compress: Map.get(headers, "x-wsproxy-compress", "false") |> String.to_existing_atom(),
      idle_timeout: Map.get(headers, "x-wsproxy-idletimeout", "60000") |> String.to_integer(),
      max_frame_size: Map.get(headers, "x-wsproxy-maxframesize", "2048") |> String.to_integer(),
      validate_utf8:
        Map.get(headers, "x-wsproxy-validateutf8", "false") |> String.to_existing_atom()
    }

    Logger.debug("http init: #{inspect(headers)}")

    upstream_headers =
      Enum.filter(headers, fn {key, _val} ->
        not String.starts_with?(key, "x-wsproxy") and
          key not in [
            "host",
            "connection",
            "upgrade",
            "sec-websocket-version",
            "sec-websocket-key"
          ]
      end) ++ [{"user-agent", "wsproxy"}]

    {:cowboy_websocket, req,
     %{
       upstream: Map.get(headers, "x-wsproxy-upstream") |> to_url(path, querystring),
       webhooks: %{
         inbound:
           {Map.get(headers, "x-wsproxy-inboundhook") |> to_url(path, querystring),
            Map.get(headers, "x-wsproxy-inboundhook-method", "POST") |> to_http_method(),
            Map.get(headers, "x-wsproxy-inboundhook-headers") |> to_http_headers()},
         outbound:
           {Map.get(headers, "x-wsproxy-outboundhook") |> to_url(path, querystring),
            Map.get(headers, "x-wsproxy-outboundhook-method", "POST") |> to_http_method(),
            Map.get(headers, "x-wsproxy-outboundhook-headers") |> to_http_headers()}
       },
       upstream_headers: upstream_headers
     }, opts}
  end

  def websocket_init(%{upstream: nil} = state) do
    Logger.error("websocket init: no upstream provided")
    {[:close], state}
  end

  def websocket_init(
        %{
          upstream: upstream_url,
          upstream_headers: upstream_headers
        } = state
      ) do
    Logger.debug("websocket init: connect to upstream #{upstream_url}")

    case WsProxy.SocketUpstream.start_link(upstream_url, self(), extra_headers: upstream_headers) do
      {:ok, pid} ->
        Logger.info("websocket init: connection established to #{upstream_url}")
        state = Map.put(state, :upstream_pid, pid)
        {[{:active, true}], state}

      {:error, reason} ->
        Logger.error("websocket init: connection setup failed due to #{inspect(reason)}")
        {[:close], state}
    end
  end

  def websocket_handle(frame, %{upstream_pid: pid} = state) do
    Logger.debug("websocket handle inbound frame: #{inspect(frame)}")

    with true <- check_hook(:inbound, frame, state),
         :ok <- WsProxy.SocketUpstream.send_data(pid, frame) do
      {[{:active, true}], state}
    else
      false ->
        Logger.debug("webhook validation for inbound frame failed, closing socket")
        {[:close], state}

      {:error, reason} ->
        Logger.error("websocket handle inbound frame: failed due to #{inspect(reason)}")
        {[:close], state}
    end
  end

  def websocket_info({:from_upstream, frame}, state) do
    Logger.debug("websocket handle outbound frame: #{inspect(frame)}")

    case check_hook(:outbound, frame, state) do
      true ->
        {[frame], state}

      false ->
        Logger.debug("webhook validation for outbound frame failed, closing socket")
        {[:close], state}
    end
  end

  def terminate(reason, _req, %{upstream_pid: pid} = _state) do
    case reason do
      :normal ->
        Logger.debug("websocket proxy connection terminated")

      :timeout ->
        Logger.debug("websocket proxy connection terminated due to timeout")

      :stop ->
        Logger.debug("websocket proxy connection terminated due to enforced stop")

      {:error, :closed} ->
        Logger.debug("websocket proxy connection terminated due to socket closed")

      reason ->
        Logger.error("websocket proxy connection terminated abnormally: #{inspect(reason)}")
    end

    Process.exit(pid, :normal)
    :ok
  end

  def terminate(_reason, _req, _state) do
    :ok
  end

  defp check_hook(hook_type, {frame_type, data}, %{webhooks: webhooks} = _state) do
    with {hook_url, hook_method, hook_headers} <- Map.fetch!(webhooks, hook_type),
         {_, true} <- {:is_hook_present, hook_url != nil},
         {_, true} <- {:is_frame_supported, frame_type == :text},
         request = Finch.build(hook_method, hook_url, hook_headers, data),
         {:ok, %Finch.Response{status: status}} <- Finch.request(request, WsProxy.WebhookPool),
         {_, _, true} <- {:is_valid_status_code, status, status in [200, 201, 202, 203, 204]} do
      Logger.debug("check #{hook_type} webhook #{hook_url}, response status #{status}")
      true
    else
      {:is_hook_present, false} ->
        true

      {:is_frame_supported, false} ->
        Logger.error("webhook unsuported frame type #{frame_type}")
        false

      {:is_valid_status_code, status, false} ->
        Logger.error("webhook invalid status code #{status}")
        false

      {:error, %Mint.TransportError{reason: reason}} ->
        Logger.error("webhook transport error #{inspect(reason)}")
        false
    end
  end

  defp to_url(nil, _, _), do: nil

  defp to_url(base_url, path, query) do
    base_url
    |> URI.parse()
    |> Map.put(:path, path)
    |> Map.put(:query, query)
    |> URI.to_string()
  end

  defp to_http_method(method_str),
    do: method_str |> String.downcase() |> String.to_existing_atom()

  defp to_http_headers(nil), do: []

  defp to_http_headers(headers_string) do
    headers_string
    |> String.split(",", trim: true)
    |> Enum.flat_map(fn header ->
      case String.split(header, "=") do
        [key, val] ->
          [{key, val}]

        _ ->
          []
      end
    end)
  end
end
