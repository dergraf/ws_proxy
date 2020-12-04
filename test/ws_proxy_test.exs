defmodule WsProxyTest do
  use ExUnit.Case
  doctest WsProxy

  test "greets the world" do
    assert WsProxy.hello() == :world
  end
end
