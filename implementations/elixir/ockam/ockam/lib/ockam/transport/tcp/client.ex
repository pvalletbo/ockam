defmodule Ockam.Transport.TCP.Client do
  @moduledoc false
  use GenServer

  alias Ockam.Message
  alias Ockam.Transport.TCPAddress

  @wire_encoder_decoder Ockam.Wire.Binary.V2

  @impl true
  def init(%{ip: ip, port: port} = state) do
    # TODO: connect/3 and controlling_process/2 should be in a callback.
    {:ok, socket} = :gen_tcp.connect(ip, port, [:binary, :inet, active: true, packet: 2])
    :gen_tcp.controlling_process(socket, self())

    {:ok, Map.put(state, :socket, socket)}
  end

  @spec start_link(map) :: :ignore | {:error, any} | {:ok, pid}
  def start_link(default) when is_map(default) do
    GenServer.start_link(__MODULE__, default)
  end

  @impl true
  def handle_info(:connect, %{ip: ip, port: port} = state) do
    {:ok, socket} = :gen_tcp.connect(ip, port, [:binary, :inet, {:packet, 2}])
    :inet.setopts(socket, [{:active, true}, {:packet, 2}])
    :gen_tcp.controlling_process(socket, self())

    {:noreply, Map.put(state, :socket, socket)}
  end

  def handle_info({:tcp, socket, data}, %{socket: socket} = state) do
    with {:ok, message} <- Ockam.Wire.decode(@wire_encoder_decoder, data),
         {:ok, message} <- update_return_route(message, state) do
      Ockam.Router.route(message)
    else
      {:error, %Ockam.Wire.DecodeError{} = e} -> raise e
      e -> raise e
    end

    {:noreply, state}
  end

  def handle_info({:tcp_closed, _}, state), do: {:stop, :normal, state}
  def handle_info({:tcp_error, _}, state), do: {:stop, :normal, state}

  @impl true
  def handle_call({:send, data}, _from, %{socket: socket} = state) do
    {:reply, :gen_tcp.send(socket, data), state}
  end

  @spec send(atom | pid | {atom, any} | {:via, atom, any}, any) :: any
  def send(pid, data) do
    GenServer.call(pid, {:send, data})
  end

  defp update_return_route(message, %{ip: ip, port: port}) do
    return_route = Message.return_route(message)
    {:ok, Map.put(message, :return_route, [%TCPAddress{ip: ip, port: port} | return_route])}
  end
end
