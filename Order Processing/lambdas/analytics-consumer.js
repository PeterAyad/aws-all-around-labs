// analytics-consumer Lambda
// Triggered by SQS: orders-analytics-queue
// Simulates writing order data to an analytics pipeline / data warehouse
//
// Environment variables:
//   PROCESSING_DELAY_MS  — how long to simulate work (default: 8000ms)
//                          Set this in the Lambda Console to slow down processing
//                          so queue depth stays visible on the dashboard.

const DELAY_MS = parseInt(process.env.PROCESSING_DELAY_MS || "8000");

export const handler = async (event) => {
  for (const record of event.Records) {
    const order = JSON.parse(record.body);

    console.log(`[ANALYTICS] Processing order ${order.orderId}`);
    console.log(`[ANALYTICS] Simulating ${DELAY_MS}ms processing time...`);

    // Simulate failure for orders with no items (poison message demo)
    if (!order.items || order.items.length === 0) {
      throw new Error(
        `[ANALYTICS] SCHEMA ERROR: Order ${order.orderId} has no items array. Cannot write to data warehouse. Moving to DLQ.`
      );
    }

    // Configurable processing delay — keeps messages visible in queue during burst demo
    await new Promise((r) => setTimeout(r, DELAY_MS));

    const analyticsRecord = {
      eventType: "ORDER_PLACED",
      orderId: order.orderId,
      customerId: order.customerName.toLowerCase().replace(/\s+/g, "_"),
      itemCount: order.items.length,
      totalUnits: order.items.reduce((sum, i) => sum + i.quantity, 0),
      orderValue: order.total,
      placedAt: order.placedAt,
      ingestedAt: new Date().toISOString(),
    };

    console.log(
      `[ANALYTICS] Writing to data warehouse:`,
      JSON.stringify(analyticsRecord, null, 2)
    );
    console.log(
      `[ANALYTICS] SUCCESS: Record ingested for order ${order.orderId}`
    );
  }
};
