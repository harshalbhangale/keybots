// Price-triggered orders: "sell 1 near if it drops below 2".
//
// An order is a trade command plus a price to wait for. The server watches the
// price on NEAR Intents' own list and, when it crosses, runs the command exactly
// as if the owner had just typed it: same token checks, same Trading Agent caps,
// same receipt. Only the owner's typed words can create one.
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { randomUUID } from "node:crypto";

export interface Order {
  id: string;
  at: string;
  /** What the owner typed. */
  text: string;
  /** The trade to run when the price crosses: "sell 1 near". */
  command: string;
  /** The token being watched. */
  symbol: string;
  direction: "below" | "above";
  /** The price to wait for, in dollars. */
  price: number;
  /** The price when the order was made. */
  priceThen: number;
  status: "watching" | "triggered" | "cancelled";
  triggeredAt?: string;
  /** The price that set it off. */
  triggeredPrice?: number;
  /** The receipt of the command it ran. */
  receiptId?: string;
}

export interface OrderStore {
  add(o: Omit<Order, "id" | "at" | "status">): Order;
  list(): Order[];
  update(id: string, patch: Partial<Order>): Order | undefined;
}

function store(read: () => Order[], write: (all: Order[]) => void): OrderStore {
  return {
    add(o) {
      const order: Order = { ...o, id: randomUUID(), at: new Date().toISOString(), status: "watching" };
      write([...read(), order]);
      return order;
    },
    list: () => [...read()].reverse(),
    update(id, patch) {
      const all = read();
      const i = all.findIndex((o) => o.id === id);
      if (i < 0) return undefined;
      all[i] = { ...all[i], ...patch };
      write(all);
      return all[i];
    },
  };
}

export function fileOrders(dir: string): OrderStore {
  mkdirSync(dir, { recursive: true });
  const file = join(dir, "orders.json");
  return store(
    () => (existsSync(file) ? (JSON.parse(readFileSync(file, "utf8")) as Order[]) : []),
    (all) => writeFileSync(file, JSON.stringify(all, null, 2)),
  );
}

export function memoryOrders(): OrderStore {
  let all: Order[] = [];
  return store(
    () => all,
    (next) => void (all = next),
  );
}

/** Has the price crossed the line the order is waiting for? */
export function crossed(order: Pick<Order, "direction" | "price">, now: number): boolean {
  return order.direction === "below" ? now <= order.price : now >= order.price;
}

/**
 * One look at every watching order. `price` gives a token's current price (or
 * undefined if it can't be had right now); `run` runs the order's command and
 * returns its receipt id. Returns the orders that triggered.
 */
export async function checkOrders(
  orders: OrderStore,
  price: (symbol: string) => Promise<number | undefined>,
  run: (command: string) => Promise<string>,
): Promise<Order[]> {
  const fired: Order[] = [];
  for (const o of orders.list().filter((x) => x.status === "watching")) {
    let now: number | undefined;
    try {
      now = await price(o.symbol);
    } catch {
      continue; // no price right now: look again next time
    }
    if (now === undefined || !crossed(o, now)) continue;
    // Mark it first, so a slow command can never run twice.
    orders.update(o.id, { status: "triggered", triggeredAt: new Date().toISOString(), triggeredPrice: now });
    let receiptId: string | undefined;
    try {
      receiptId = await run(o.command);
    } catch {
      receiptId = undefined;
    }
    const done = orders.update(o.id, { receiptId });
    if (done) fired.push(done);
  }
  return fired;
}
