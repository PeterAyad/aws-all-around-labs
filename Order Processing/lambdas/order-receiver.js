// order-receiver Lambda
// Triggered by API Gateway POST /orders
// Publishes the order to SNS for fan-out

import { SNSClient, PublishCommand } from "@aws-sdk/client-sns";

const sns = new SNSClient({});

export const handler = async (event) => {
  const headers = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "Content-Type",
    "Content-Type": "application/json",
  };

  // Handle CORS preflight
  if (event.httpMethod === "OPTIONS") {
    return { statusCode: 200, headers, body: "" };
  }

  let body;
  try {
    body = JSON.parse(event.body || "{}");
  } catch {
    return {
      statusCode: 400,
      headers,
      body: JSON.stringify({ error: "Invalid JSON body" }),
    };
  }

  const { customerName, items, total } = body;

  if (!customerName || !items || !total) {
    return {
      statusCode: 400,
      headers,
      body: JSON.stringify({
        error: "Missing required fields: customerName, items, total",
      }),
    };
  }

  const order = {
    orderId: `ORD-${Date.now()}-${Math.random().toString(36).slice(2, 7).toUpperCase()}`,
    customerName,
    items,
    total,
    placedAt: new Date().toISOString(),
    status: "received",
  };

  const command = new PublishCommand({
    TopicArn: process.env.ORDERS_TOPIC_ARN,
    Message: JSON.stringify(order),
    Subject: "New Order Placed",
    MessageAttributes: {
      eventType: {
        DataType: "String",
        StringValue: "ORDER_PLACED",
      },
    },
  });

  await sns.send(command);

  return {
    statusCode: 202,
    headers,
    body: JSON.stringify({
      message: "Order accepted and dispatched for processing",
      orderId: order.orderId,
      placedAt: order.placedAt,
    }),
  };
};
