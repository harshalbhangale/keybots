// npm run try -- "pay harshal 0.2 for dinner" [--pasted]
// npm run try -- --call      (a dry review of the first call in the KOL feed)
// A dry run against the live leash: public RPC view calls and quotes only.
// No keys are read and nothing is sent: --call reviews, it never confirms.
import { loadConfig } from "./config.js";
import { dryRun, format } from "./dryrun.js";
import { intentsClient } from "./intents.js";
import { kallClient } from "./kall.js";
import { nearChain } from "./near.js";
import { memoryStore } from "./receipts.js";
import { rheaClient } from "./rhea.js";
import { TradeError, tradeFlow } from "./trade.js";

const args = process.argv.slice(2);
const pasted = args.includes("--pasted");
const call = args.includes("--call");
const text = args.filter((a) => a !== "--pasted" && a !== "--call").join(" ").trim();
if (!text && !call) {
  console.log('Usage: npm run try -- "pay harshal 0.2 for dinner" [--pasted]\n       npm run try -- --call');
  process.exit(1);
}
const cfg = loadConfig();
// nearChain only reads a key when an agent signs; the dry run never signs.
const deps = {
  cfg,
  chain: nearChain(cfg),
  rhea: rheaClient({ network: cfg.network, rpc: cfg.rpc }),
  intents: intentsClient({ recipient: cfg.owner }),
};
try {
  if (call) {
    const flow = tradeFlow({ ...deps, receipts: memoryStore(), kall: kallClient(cfg.kallApi) });
    const feed = await flow.feed();
    console.log(`Feed: ${feed.source}, ${feed.calls.length} calls. ${feed.note ?? ""}`.trim());
    // The first call that reviews; the ones before it say why they didn't.
    for (const c of feed.calls) {
      try {
        const review = await flow.review({ callId: c.id });
        console.log(`Review of ${c.id} (@${c.author.handle}), dry: nothing is confirmed or sent.`);
        console.log(JSON.stringify(review, null, 2));
        process.exit(0);
      } catch (e) {
        if (!(e instanceof TradeError)) throw e;
        console.log(`${c.id} (@${c.author.handle}, ${c.direction} ${c.asset}): ${e.message}`);
      }
    }
    console.log("No call in the feed could be reviewed.");
  } else {
    console.log(format(await dryRun(deps, text, { pasted })));
  }
} catch (e) {
  console.error(`Couldn't read the leash: ${(e as Error).message}`);
  process.exit(1);
}
