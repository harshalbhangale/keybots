// npm run try -- "pay harshal 0.2 for dinner" [--pasted]
// A dry run against the live leash: public RPC view calls and quotes only.
// No keys are read and nothing is sent.
import { loadConfig } from "./config.js";
import { dryRun, format } from "./dryrun.js";
import { intentsClient } from "./intents.js";
import { nearChain } from "./near.js";
import { rheaClient } from "./rhea.js";

const args = process.argv.slice(2);
const pasted = args.includes("--pasted");
const text = args.filter((a) => a !== "--pasted").join(" ").trim();
if (!text) {
  console.log('Usage: npm run try -- "pay harshal 0.2 for dinner" [--pasted]');
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
  console.log(format(await dryRun(deps, text, { pasted })));
} catch (e) {
  console.error(`Couldn't read the leash: ${(e as Error).message}`);
  process.exit(1);
}
