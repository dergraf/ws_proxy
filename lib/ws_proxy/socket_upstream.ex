defmodule WsProxy.SocketUpstream do
  use WebSockex

  def start_link(url, downstream_pid, options) do
    WebSockex.start_link(url, __MODULE__, %{downstream_pid: downstream_pid}, options)
  end

  def send_data(pid, data) do
    WebSockex.send_frame(pid, data)
  end

  def handle_frame(frame, %{downstream_pid: downstream_pid} = state) do
    Process.send(downstream_pid, {:from_upstream, frame}, [])
    {:ok, state}
  end
end
