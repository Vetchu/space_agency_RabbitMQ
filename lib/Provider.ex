defmodule Provider do
  use GenServer
  use AMQP

  @exchange "space_agencies"
  def uuid do
    "#{inspect(self())}#{inspect(node())}"
  end

  def start_link(name, offers) do
    GenServer.start_link(__MODULE__, {name, offers}, [])
  end

  @impl true
  def init({name, offers}) do
    IO.puts("Provider #{uuid()}{")
    {:ok, connection} = Connection.open()
    {:ok, channel} = Channel.open(connection)
    Basic.qos(channel, prefetch_count: 1)

    Exchange.topic(channel, @exchange, durable: true)

    Enum.each(
      offers,
      fn offer ->
        IO.puts(" [*] Binding queue #{offer} to exchange")
        {:ok, _} = Queue.declare(channel, offer)
        {:ok, _} = Basic.consume(channel, offer)
        Queue.bind(channel, offer, @exchange, routing_key: offer)
      end
    )

    {:ok, %{queue: admin_queue}} = Queue.declare(channel, "", exclusive: true)
    Basic.consume(channel, admin_queue)
    Queue.bind(channel, admin_queue, @exchange, routing_key: "admin.all")
    Queue.bind(channel, admin_queue, @exchange, routing_key: "admin.provider")

    IO.puts(" [*] RabbitMQ Provider connected")
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
      IO.puts(" [***] [#{this_uuid} Provider]: \n  Admin message: #{payload}\n")
      Basic.ack(chan, meta.delivery_tag)
    else
      spawn(fn ->
        consume(chan, meta.delivery_tag, meta.routing_key, meta.reply_to, payload, this_uuid)
      end)
    end

    {:noreply, chan}
  end

  defp consume(channel, tag, request, agency, payload, uuid) do
    try do
      IO.puts(" [*] [#{uuid} Provider]: \n Request: #{request} from #{agency}  \n Confirm #{payload} to #{agency}\n")
      Basic.ack(channel, tag)
      Basic.publish(channel, @exchange, agency, "#{payload}", reply_to: uuid)
    rescue
      exception ->
        IO.puts(exception)
        # Basic.reject(channel, tag, requeue: not redelivered)
    end
  end
end
