defmodule Agency do
  use GenServer
  use AMQP

  @exchange "space_agencies"
  @offers ["satellite", "personal", "load"]

  def uuid do
    "#{inspect(self())}#{inspect(node())}"
  end

  def start_link(name) do
    GenServer.start_link(__MODULE__, name, [])
  end

  @impl true
  def init(name) do
    IO.puts("Agency #{uuid()}{")
    {:ok, connection} = Connection.open()
    {:ok, channel} = Channel.open(connection)

    :ok = Basic.qos(channel, prefetch_count: 1)
    Exchange.topic(channel, @exchange, durable: true)

    {:ok, %{queue: _queue_name}} = Queue.declare(channel, name)
    {:ok, _consumer_tag} = Basic.consume(channel, name, nil)
    Queue.bind(channel, name, @exchange, routing_key: uuid())

    {:ok, %{queue: admin_queue}} = Queue.declare(channel, "", exclusive: true)
    Basic.consume(channel, admin_queue)
    Queue.bind(channel, admin_queue, @exchange, routing_key: "admin.all")
    Queue.bind(channel, admin_queue, @exchange, routing_key: "admin.agency")

    IO.puts(" [*] RabbitMQ Agency connected")
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

    if(String.contains?("#{meta.routing_key}", "admin")) do
      IO.puts(" [***] [#{this_uuid} Agency]: \n  Admin message: #{payload}\n")
      Basic.ack(chan, meta.delivery_tag)
    else
      spawn(fn -> consume(chan, meta.delivery_tag, meta.reply_to, payload, this_uuid) end)
    end

    {:noreply, chan}
  end

  defp consume(channel, tag, providerID, payload, uuid) do
    try do
      IO.puts(
        " [*] [#{uuid} Agency]: Confirmed: \n #{providerID} completed a request no. #{payload}\n"
      )

      Basic.ack(channel, tag)
    rescue
      exception ->
        IO.puts(exception)
        # Basic.reject(channel, tag, requeue: not redelivered)
    end
  end

  @impl true
  def handle_cast({:order, offer}, chan) do
    if(Enum.member?(@offers, offer)) do
      agency_id = uuid()

      spawn(fn ->
        msg_uuid = UUID.uuid1()
        :ok = Basic.publish(chan, "", offer, "#{msg_uuid}", reply_to: agency_id)
        IO.puts(" [x] Sent request no #{msg_uuid}' to #{offer} queue")
      end)
    else
      IO.puts(" [x] Incorrect offer request provided: #{offer}")
    end

    {:noreply, chan}
  end
end
