// queue-status Lambda
// Called by the dashboard via API Gateway GET /status
// Returns approximate message counts for all queues and DLQs

import { SQSClient, GetQueueAttributesCommand } from "@aws-sdk/client-sqs";
import {
  CloudWatchLogsClient,
  FilterLogEventsCommand,
} from "@aws-sdk/client-cloudwatch-logs";

const sqs = new SQSClient({});
const logs = new CloudWatchLogsClient({});

const QUEUES = {
  inventory: {
    url: process.env.INVENTORY_QUEUE_URL,
    dlq: process.env.INVENTORY_DLQ_URL,
    label: "Inventory",
    logGroup: "/aws/lambda/inventory-consumer",
  },
  notification: {
    url: process.env.NOTIFICATION_QUEUE_URL,
    dlq: process.env.NOTIFICATION_DLQ_URL,
    label: "Notification",
    logGroup: "/aws/lambda/notification-consumer",
  },
  analytics: {
    url: process.env.ANALYTICS_QUEUE_URL,
    dlq: process.env.ANALYTICS_DLQ_URL,
    label: "Analytics",
    logGroup: "/aws/lambda/analytics-consumer",
  },
};

async function getQueueDepth(queueUrl) {
  if (!queueUrl) return { messages: 0, inFlight: 0 };
  try {
    const cmd = new GetQueueAttributesCommand({
      QueueUrl: queueUrl,
      AttributeNames: [
        "ApproximateNumberOfMessages",
        "ApproximateNumberOfMessagesNotVisible",
      ],
    });
    const res = await sqs.send(cmd);
    return {
      messages: parseInt(res.Attributes.ApproximateNumberOfMessages || "0"),
      inFlight: parseInt(
        res.Attributes.ApproximateNumberOfMessagesNotVisible || "0"
      ),
    };
  } catch {
    return { messages: 0, inFlight: 0 };
  }
}

async function getRecentLogs(logGroup) {
  try {
    const cmd = new FilterLogEventsCommand({
      logGroupName: logGroup,
      startTime: Date.now() - 10 * 60 * 1000, // last 10 minutes
      limit: 20,
      filterPattern: "SUCCESS OR ERROR",
    });
    const res = await logs.send(cmd);
    return (res.events || []).map((e) => ({
      time: new Date(e.timestamp).toISOString(),
      message: e.message.trim(),
    }));
  } catch {
    return [];
  }
}

export const handler = async () => {
  const headers = {
    "Access-Control-Allow-Origin": "*",
    "Content-Type": "application/json",
  };

  const results = await Promise.all(
    Object.entries(QUEUES).map(async ([key, q]) => {
      const [queue, dlq, recentLogs] = await Promise.all([
        getQueueDepth(q.url),
        getQueueDepth(q.dlq),
        getRecentLogs(q.logGroup),
      ]);
      return {
        id: key,
        label: q.label,
        queue,
        dlq,
        recentLogs,
      };
    })
  );

  return {
    statusCode: 200,
    headers,
    body: JSON.stringify({
      timestamp: new Date().toISOString(),
      queues: results,
    }),
  };
};
