"""
consumer.py — Warehouse Inventory System Simulator
Receives and acknowledges "Order Placed" messages from Amazon MQ (RabbitMQ engine).

Usage:
    python consumer.py --host <broker-host> --user <username> --password <password>

Press Ctrl+C to stop.
"""

import pika
import json
import argparse
import ssl 

context = ssl.create_default_context()

QUEUE_NAME = "orders"

def get_args():
    parser = argparse.ArgumentParser(description="Warehouse System - Order Consumer")
    parser.add_argument("--host",     required=True, help="Amazon MQ broker hostname (without amqps://)")
    parser.add_argument("--user",     required=True, help="Broker username")
    parser.add_argument("--password", required=True, help="Broker password")
    parser.add_argument("--port",     default=5671,  type=int, help="AMQP TLS port (default: 5671)")
    return parser.parse_args()

def on_message(channel, method, properties, body):
    """Called automatically each time a message is delivered."""
    try:
        order = json.loads(body)
        print(f"[WH]  ✔ Received order  → ID: {order['order_id']} | "
              f"Product: {order['product']} | Qty: {order['quantity']} | "
              f"Time: {order['timestamp']}")
    except json.JSONDecodeError:
        print(f"[WH]  ⚠ Could not parse message: {body}")

    # Acknowledge so the broker removes the message from the queue
    channel.basic_ack(delivery_tag=method.delivery_tag)

def main():
    args = get_args()

    # ------------------------------------------------------------------ #
    #  Connect to Amazon MQ using TLS (port 5671)                         #
    # ------------------------------------------------------------------ #
    credentials = pika.PlainCredentials(args.user, args.password)
    ssl_options  = pika.SSLOptions(context=context)
    parameters   = pika.ConnectionParameters(
        host        = args.host,
        port        = args.port,
        credentials = credentials,
        ssl_options = ssl_options,
    )

    print(f"[WH]  Connecting to broker at {args.host}:{args.port} ...")
    connection = pika.BlockingConnection(parameters)
    channel    = connection.channel()

    # Declare the queue (idempotent — must match producer declaration)
    channel.queue_declare(queue=QUEUE_NAME, durable=True)

    # Process one message at a time (fair dispatch)
    channel.basic_qos(prefetch_count=1)
    channel.basic_consume(queue=QUEUE_NAME, on_message_callback=on_message)

    print(f"[WH]  Waiting for orders on queue '{QUEUE_NAME}'. Press Ctrl+C to stop.\n")
    try:
        channel.start_consuming()
    except KeyboardInterrupt:
        print("\n[WH]  Stopped.")
        connection.close()

if __name__ == "__main__":
    main()
