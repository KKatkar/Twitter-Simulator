defmodule Proj41 do

  require Logger
  def main(args) do
    {_, args, _} = OptionParser.parse(args)
    port = 8888
    mode = Enum.at(args, 0)
    if mode == "server" do
      Logger.debug "Initiating Engine..."
      Server.start_link(port)
    else
#assign ip_address to server
      server_ip = parse_ip(Enum.at(args, 1))
      if mode == "client" do
        Logger.debug "Connecting to twitter-engine..."
        {:ok, socket} = make_connection(server_ip, port)
        Logger.debug "Connected"
        Logger.debug "Starting as Client Interface"
        Client.start_link(socket)
      else #case for simulator
        Logger.debug "Starting simulator"
        user_count = Enum.at(args, 2) |> String.to_integer
        subprocess_count = if length(args) == 4 do
          Enum.at(args, 3) |> String.to_integer
        else
          1
        end

        for _clients <- 1..subprocess_count do
          Logger.debug "Connecting to twitter-engine..."
          {:ok, socket} = make_connection(server_ip, port)
          Logger.debug "Connected"
          spawn fn -> Client.simulate(socket, user_count) end
        end
        keep_server_alive()
      end
    end
  end

  def keep_server_alive() do
      :timer.sleep 10000
      keep_server_alive()
  end

  defp parse_ip(str) do
    [a, b, c, d] = String.split(str, ".")
    {String.to_integer(a), String.to_integer(b), String.to_integer(c), String.to_integer(d)}
  end

  defp make_connection(server_ip, port) do
    :gen_tcp.connect(server_ip, port, [:binary, {:active, false},{:packet, 0}])
  end
end
