defmodule Admin do
  use GenServer
  use AMQP

  @exchange "space_agencies"

  def uuid do
    "#{inspect(self())}#{inspect(node())}"
  end

  def start_link(name) do
    GenServer.start_link(__MODULE__, name, [])
  end

  @impl true
  def init(name) do
    IO.puts("Admin #{uuid()}{")

    {:ok, connection} = Connection.open()
    {:ok, channel} = Channel.open(connection)

    :ok = Basic.qos(channel, prefetch_count: 1)

    {:ok, %{queue: _queue_name}} = Queue.declare(channel, name)
    {:ok, _consumer_tag} = Basic.consume(channel, name)
    Exchange.topic(channel, @exchange, durable: true)
    Queue.bind(channel, name, @exchange, routing_key: "#")

    IO.puts(" [*] RabbitMQ Admin connected")
    IO.puts("}")

    {:ok, channel}
  end

  # Confirmation sent by the broker after registering this process as a consumer
  @impl true
  def handle_info({:basic_consume_ok, %{consumer_tag: _consumer_tag}}, chan) do
    {:noreply, chan}
  end

  # Sent by the broker when the consumer is unexpectedly cancelled (such as after a queue deletion)
  def handle_info({:basic_cancel, %{consumer_tag: _consumer_tag}}, chan) do
    {:stop, :normal, chan}
  end

  # Confirmation sent by the broker to the consumer process after a Basic.cancel
  def handle_info({:basic_cancel_ok, %{consumer_tag: _consumer_tag}}, chan) do
    {:noreply, chan}
  end

  def handle_info({:basic_deliver, payload, meta}, chan) do
    this_uuid = uuid()

    spawn(fn ->
      consume(chan, meta.delivery_tag, meta.reply_to, meta.routing_key, payload, this_uuid)
    end)

    {:noreply, chan}
  end

  defp consume(channel, tag, fromID, key, payload, uuid) do
    try do
      IO.puts(" [***] [#{uuid} Admin]:
        frm: #{fromID}
        to : #{key}
        msg: #{payload}\n"
      )
      Basic.ack(channel, tag)
    rescue
      exception ->
        IO.puts(exception)
        Basic.reject(channel, tag)
    end
  end

  @impl true
  def handle_cast({:to_provider, msg}, chan) do
    admin_id = uuid()

    spawn(fn ->
      :ok = Basic.publish(chan, @exchange, "admin.provider", msg, reply_to: admin_id)
      IO.puts(" [x] [#{admin_id} Admin] Sent message #{msg} to providers")
    end)

    {:noreply, chan}
  end

  @impl true
    def handle_cast({:to_agency, msg}, chan) do
    admin_id = uuid()

    spawn(fn ->
      :ok = Basic.publish(chan, @exchange, "admin.agency", msg, reply_to: admin_id)
      IO.puts(" [x] [#{admin_id} Admin] Sent message #{msg} to agencies")
    end)

    {:noreply, chan}
  end

  @impl true
  def handle_cast({:to_all, msg}, chan) do
    admin_id = uuid()

    spawn(fn ->
      :ok = Basic.publish(chan, @exchange, "admin.all", msg, reply_to: admin_id)
      IO.puts(" [x] [#{admin_id} Admin] Sent message #{msg} to all")
    end)

    {:noreply, chan}
  end
end
