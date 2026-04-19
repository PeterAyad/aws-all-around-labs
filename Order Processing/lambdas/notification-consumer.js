// notification-consumer Lambda
// Triggered by SQS: orders-notification-queue
// Simulates sending an order confirmation email to the customer
//
// Environment variables:
//   PROCESSING_DELAY_MS  — how long to simulate work (default: 8000ms)
//                          Set this in the Lambda Console to slow down processing
//                          so queue depth stays visible on the dashboard.

const DELAY_MS = parseInt(process.env.PROCESSING_DELAY_MS || "8000");

export const handler = async (event) => {
  for (const record of event.Records) {
    const order = JSON.parse(record.body);

    console.log(`[NOTIFICATION] Processing order ${order.orderId}`);
    console.log(`[NOTIFICATION] Sending confirmation to: ${order.customerName}`);
    console.log(`[NOTIFICATION] Simulating ${DELAY_MS}ms processing time...`);

    // Simulate failure for orders with total > 9999 (poison message demo)
    if (order.total > 9999) {
      throw new Error(
        `[NOTIFICATION] EMAIL ERROR: Order total $${order.total} exceeds fraud threshold. Flagged and moved to DLQ.`
      );
    }

    // Configurable processing delay — keeps messages visible in queue during burst demo
    await new Promise((r) => setTimeout(r, DELAY_MS));

    const emailBody = `
      Dear ${order.customerName},

      Thank you for your order!

      Order ID   : ${order.orderId}
      Placed At  : ${order.placedAt}
      Items      : ${order.items.map((i) => `${i.quantity}x ${i.name}`).join(", ")}
      Total      : $${order.total.toFixed(2)}

      Your order is being processed and will ship soon.

      — The Lab Store Team
    `;

    console.log(`[NOTIFICATION] Email body:\n${emailBody}`);
    console.log(
      `[NOTIFICATION] SUCCESS: Confirmation sent for order ${order.orderId}`
    );
  }
};
