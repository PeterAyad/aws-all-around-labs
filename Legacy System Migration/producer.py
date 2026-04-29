"""
producer.py — Point-of-Sale Terminal Simulator
Sends "Order Placed" messages to Amazon MQ (RabbitMQ engine) via AMQP.

Usage:
    python producer.py --host <broker-host> --user <username> --password <password>
"""

import pika
import json
import time
import random
import argparse
import ssl 

context = ssl.create_default_context()

QUEUE_NAME = "orders"

PRODUCTS = ["Widget A", "Gadget B", "Doohickey C", "Thingamajig D", "Whatsit E"]

def get_args():
    parser = argparse.ArgumentParser(description="POS Terminal - Order Producer")
    parser.add_argument("--host",     required=True, help="Amazon MQ broker hostname (without amqps://)")
    parser.add_argument("--user",     required=True, help="Broker username")
    parser.add_argument("--password", required=True, help="Broker password")
    parser.add_argument("--port",     default=5671,  type=int, help="AMQP TLS port (default: 5671)")
    parser.add_argument("--count",    default=5,     type=int, help="Number of orders to send (default: 5)")
    return parser.parse_args()

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

    print(f"[POS] Connecting to broker at {args.host}:{args.port} ...")
    connection = pika.BlockingConnection(parameters)
    channel    = connection.channel()

    # Declare the queue (idempotent — safe to run multiple times)
    channel.queue_declare(queue=QUEUE_NAME, durable=True)

    # ------------------------------------------------------------------ #
    #  Publish orders                                                      #
    # ------------------------------------------------------------------ #
    for i in range(1, args.count + 1):
        order = {
            "order_id":  f"ORD-{random.randint(1000, 9999)}",
            "product":   random.choice(PRODUCTS),
            "quantity":  random.randint(1, 10),
            "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        }
        body = json.dumps(order)

        channel.basic_publish(
            exchange    = "",
            routing_key = QUEUE_NAME,
            body        = body,
            properties  = pika.BasicProperties(delivery_mode=2),  # persistent
        )
        print(f"[POS]  Sent order {i}/{args.count}: {body}")
        time.sleep(0.5)

    connection.close()
    print("[POS] All orders sent. Connection closed.")

if __name__ == "__main__":
    main()
