// inventory-consumer Lambda
// Triggered by SQS: orders-inventory-queue
// Simulates reserving stock for each item in the order
//
// Environment variables:
//   PROCESSING_DELAY_MS  — how long to simulate work (default: 8000ms)
//                          Set this in the Lambda Console to slow down processing
//                          so queue depth stays visible on the dashboard.

const DELAY_MS = parseInt(process.env.PROCESSING_DELAY_MS || "8000");

export const handler = async (event) => {
  for (const record of event.Records) {
    const order = JSON.parse(record.body);

    console.log(`[INVENTORY] Processing order ${order.orderId}`);
    console.log(`[INVENTORY] Customer: ${order.customerName}`);
    console.log(`[INVENTORY] Items to reserve:`, JSON.stringify(order.items));
    console.log(`[INVENTORY] Simulating ${DELAY_MS}ms processing time...`);

    // Simulate inventory check — fail if any item quantity > 99 (poison message demo)
    for (const item of order.items) {
      if (item.quantity > 99) {
        throw new Error(
          `[INVENTORY] STOCK ERROR: quantity ${item.quantity} exceeds warehouse limit for item "${item.name}". Moving to DLQ.`
        );
      }
    }

    // Configurable processing delay — keeps messages visible in queue during burst demo
    await new Promise((r) => setTimeout(r, DELAY_MS));

    console.log(
      `[INVENTORY] SUCCESS: Stock reserved for order ${order.orderId}`
    );
  }
};
