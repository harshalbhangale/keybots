//! AirKey leash: the only way an AirKey agent can move money.
//!
//! Each agent is a NEAR account whose only key is a function-call key for this
//! contract. The leash holds the NEAR and decides every payment against the
//! owner's rules. RULES.md lists the rules in order; the tests below follow it.

use near_sdk::serde_json::json;
use near_sdk::store::{IterableMap, IterableSet};
use near_sdk::{
    env, near, require, AccountId, BorshStorageKey, Gas, NearToken, PanicOnDefault, Promise,
};

const NS_PER_DAY: u64 = 86_400_000_000_000;
const GAS_FOR_CALLBACK: Gas = Gas::from_tgas(10);
const MAX_MEMO: usize = 140;
const MAX_EVIDENCE: usize = 280;

#[derive(BorshStorageKey)]
#[near]
enum StorageKey {
    Agents,
    Allowlist,
    Blocklist,
    Pending,
}

#[near(serializers = [borsh, json])]
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
#[serde(rename_all = "snake_case")]
pub enum Tier {
    /// Acts on what the owner typed.
    Trusted,
    /// Acts on text that came from someone else.
    Untrusted,
}

#[near(serializers = [borsh, json])]
#[derive(Clone, Debug)]
pub struct Agent {
    pub tier: Tier,
    pub per_payment_cap: NearToken,
    pub daily_cap: NearToken,
    pub spent_today: NearToken,
    /// UTC day (block time / 1 day) that `spent_today` belongs to.
    pub day: u64,
}

#[near(serializers = [borsh, json])]
#[derive(Clone, Debug)]
pub struct Pending {
    pub id: u64,
    pub agent: AccountId,
    pub receiver: AccountId,
    pub amount: NearToken,
    pub memo: Option<String>,
    /// The rule that sent it here (R6 or R7).
    pub rule: String,
    pub reason: String,
    pub created_at_ns: u64,
}

#[near(serializers = [json])]
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
#[serde(rename_all = "snake_case")]
pub enum Status {
    Paid,
    Pending,
    Blocked,
}

#[near(serializers = [json])]
#[derive(Clone, Debug)]
pub struct Decision {
    pub status: Status,
    /// Which rule decided, e.g. "R4". None when paid.
    pub rule: Option<String>,
    pub reason: String,
    pub pending_id: Option<u64>,
}

impl Decision {
    fn blocked(rule: &str, reason: String) -> Self {
        Self { status: Status::Blocked, rule: Some(rule.into()), reason, pending_id: None }
    }
}

#[near(contract_state)]
#[derive(PanicOnDefault)]
pub struct Leash {
    owner: AccountId,
    paused: bool,
    agents: IterableMap<AccountId, Agent>,
    allowlist: IterableSet<AccountId>,
    /// Blocked account -> reason or evidence.
    blocklist: IterableMap<AccountId, String>,
    pending: IterableMap<u64, Pending>,
    next_id: u64,
}

fn today() -> u64 {
    env::block_timestamp() / NS_PER_DAY
}

fn emit(event: &str, data: near_sdk::serde_json::Value) {
    env::log_str(&format!(
        "EVENT_JSON:{}",
        json!({"standard": "airkey", "version": "1.0.0", "event": event, "data": [data]})
    ));
}

fn clip(s: Option<String>, max: usize) -> Option<String> {
    s.map(|s| s.chars().take(max).collect())
}

#[near]
impl Leash {
    #[init]
    pub fn new(owner: AccountId) -> Self {
        Self {
            owner,
            paused: false,
            agents: IterableMap::new(StorageKey::Agents),
            allowlist: IterableSet::new(StorageKey::Allowlist),
            blocklist: IterableMap::new(StorageKey::Blocklist),
            pending: IterableMap::new(StorageKey::Pending),
            next_id: 0,
        }
    }

    // ---------- money in and out ----------

    /// Anyone can top up the leash.
    #[payable]
    pub fn fund(&mut self) {
        emit("funded", json!({"by": env::predecessor_account_id(), "amount": env::attached_deposit()}));
    }

    /// NEAR the leash can spend now: balance minus what storage needs.
    pub fn available(&self) -> NearToken {
        let locked = env::storage_byte_cost().saturating_mul(env::storage_usage() as u128);
        env::account_balance().saturating_sub(locked)
    }

    // ---------- the agent's side ----------

    /// An agent asks to pay. See RULES.md for the order of the rules.
    pub fn pay(
        &mut self,
        receiver: AccountId,
        amount: NearToken,
        memo: Option<String>,
        ask_owner: Option<bool>,
    ) -> Decision {
        let agent_id = env::predecessor_account_id();
        let memo = clip(memo, MAX_MEMO);
        let decision = self.decide(&agent_id, &receiver, amount, memo.clone(), ask_owner.unwrap_or(false));
        match decision.status {
            Status::Paid => {
                emit(
                    "paid",
                    json!({"agent": agent_id, "receiver": receiver, "amount": amount, "memo": memo}),
                );
                self.transfer(agent_id, receiver, amount, None);
            }
            Status::Pending => emit(
                "pending",
                json!({"id": decision.pending_id, "agent": agent_id, "receiver": receiver,
                       "amount": amount, "memo": memo, "rule": decision.rule, "reason": decision.reason}),
            ),
            Status::Blocked => emit(
                "blocked",
                json!({"agent": agent_id, "receiver": receiver, "amount": amount, "memo": memo,
                       "rule": decision.rule, "reason": decision.reason}),
            ),
        }
        decision
    }

    /// An agent reports an account as a scam, with evidence. It is blocked at once.
    pub fn report(&mut self, account: AccountId, evidence: String) {
        let by = env::predecessor_account_id();
        require!(by == self.owner || self.agents.contains_key(&by), "Only the owner or an agent can report");
        let evidence: String = evidence.chars().take(MAX_EVIDENCE).collect();
        self.blocklist.insert(account.clone(), format!("reported by {by}: {evidence}"));
        emit("reported", json!({"account": account, "by": by, "evidence": evidence}));
    }

    // ---------- the owner's side (full-access key: 1 yoctoNEAR attached) ----------

    #[payable]
    pub fn add_agent(&mut self, agent: AccountId, tier: Tier, per_payment_cap: NearToken, daily_cap: NearToken) {
        self.assert_owner();
        require!(per_payment_cap <= daily_cap, "per_payment_cap must not exceed daily_cap");
        let (spent_today, day) = match self.agents.get(&agent) {
            Some(a) => (a.spent_today, a.day),
            None => (NearToken::from_yoctonear(0), today()),
        };
        self.agents.insert(agent.clone(), Agent { tier, per_payment_cap, daily_cap, spent_today, day });
        emit("agent_set", json!({"agent": agent, "tier": tier, "per_payment_cap": per_payment_cap, "daily_cap": daily_cap}));
    }

    #[payable]
    pub fn remove_agent(&mut self, agent: AccountId) {
        self.assert_owner();
        self.agents.remove(&agent);
        emit("agent_removed", json!({"agent": agent}));
    }

    #[payable]
    pub fn allow(&mut self, account: AccountId) {
        self.assert_owner();
        self.allowlist.insert(account.clone());
        emit("allowed", json!({"account": account}));
    }

    #[payable]
    pub fn disallow(&mut self, account: AccountId) {
        self.assert_owner();
        self.allowlist.remove(&account);
        emit("disallowed", json!({"account": account}));
    }

    #[payable]
    pub fn block(&mut self, account: AccountId, reason: String) {
        self.assert_owner();
        let reason: String = reason.chars().take(MAX_EVIDENCE).collect();
        self.blocklist.insert(account.clone(), reason.clone());
        emit("blocked_account", json!({"account": account, "reason": reason}));
    }

    #[payable]
    pub fn unblock(&mut self, account: AccountId) {
        self.assert_owner();
        self.blocklist.remove(&account);
        emit("unblocked_account", json!({"account": account}));
    }

    /// The kill switch.
    #[payable]
    pub fn set_paused(&mut self, paused: bool) {
        self.assert_owner();
        self.paused = paused;
        emit(if paused { "paused" } else { "resumed" }, json!({}));
    }

    /// Approve a pending payment. R1 and R3 are checked again; caps are not.
    #[payable]
    pub fn approve(&mut self, id: u64) -> Decision {
        self.assert_owner();
        let p = self.pending.remove(&id).unwrap_or_else(|| env::panic_str("No such pending payment"));
        if self.paused {
            emit("blocked", json!({"id": id, "rule": "R1", "reason": "Kill switch is on"}));
            return Decision::blocked("R1", "Kill switch is on".into());
        }
        if let Some(why) = self.blocklist.get(&p.receiver) {
            let reason = format!("{} is blocked: {}", p.receiver, why);
            emit("blocked", json!({"id": id, "rule": "R3", "reason": reason}));
            return Decision::blocked("R3", reason);
        }
        if p.amount > self.available() {
            emit("blocked", json!({"id": id, "rule": "R0", "reason": "The leash doesn't hold enough NEAR"}));
            return Decision::blocked("R0", "The leash doesn't hold enough NEAR".into());
        }
        if let Some(a) = self.agents.get_mut(&p.agent) {
            if a.day != today() {
                a.day = today();
                a.spent_today = NearToken::from_yoctonear(0);
            }
            a.spent_today = a.spent_today.saturating_add(p.amount);
        }
        emit("approved", json!({"id": id, "agent": p.agent, "receiver": p.receiver, "amount": p.amount, "memo": p.memo}));
        self.transfer(p.agent.clone(), p.receiver.clone(), p.amount, Some(id));
        Decision { status: Status::Paid, rule: None, reason: "Approved by the owner".into(), pending_id: Some(id) }
    }

    #[payable]
    pub fn reject(&mut self, id: u64) {
        self.assert_owner();
        let p = self.pending.remove(&id).unwrap_or_else(|| env::panic_str("No such pending payment"));
        emit("rejected", json!({"id": id, "agent": p.agent, "receiver": p.receiver, "amount": p.amount}));
    }

    #[payable]
    pub fn withdraw(&mut self, amount: NearToken) -> Promise {
        self.assert_owner();
        require!(amount <= self.available(), "Not enough available NEAR");
        emit("withdrawn", json!({"amount": amount}));
        Promise::new(self.owner.clone()).transfer(amount)
    }

    // ---------- callback ----------

    /// Rolls the spend back if the transfer failed.
    #[private]
    pub fn on_transfer(&mut self, agent: AccountId, receiver: AccountId, amount: NearToken, day: u64, pending_id: Option<u64>) -> bool {
        let ok = env::promise_result_checked(0, 64).is_ok();
        if !ok {
            if let Some(a) = self.agents.get_mut(&agent) {
                if a.day == day {
                    a.spent_today = a.spent_today.saturating_sub(amount);
                }
            }
            emit(
                "transfer_failed",
                json!({"agent": agent, "receiver": receiver, "amount": amount, "pending_id": pending_id}),
            );
        }
        ok
    }

    // ---------- views ----------

    pub fn get_owner(&self) -> AccountId {
        self.owner.clone()
    }

    pub fn is_paused(&self) -> bool {
        self.paused
    }

    pub fn get_agent(&self, agent: AccountId) -> Option<Agent> {
        self.agents.get(&agent).map(|a| {
            let mut a = a.clone();
            if a.day != today() {
                a.spent_today = NearToken::from_yoctonear(0);
                a.day = today();
            }
            a
        })
    }

    pub fn list_agents(&self) -> Vec<(AccountId, Agent)> {
        self.agents.iter().map(|(k, _)| (k.clone(), self.get_agent(k.clone()).unwrap())).collect()
    }

    pub fn list_pending(&self) -> Vec<Pending> {
        self.pending.values().cloned().collect()
    }

    pub fn is_allowed(&self, account: AccountId) -> bool {
        self.allowlist.contains(&account)
    }

    pub fn list_allowed(&self) -> Vec<AccountId> {
        self.allowlist.iter().cloned().collect()
    }

    pub fn blocked_reason(&self, account: AccountId) -> Option<String> {
        self.blocklist.get(&account).cloned()
    }

    pub fn list_blocked(&self) -> Vec<(AccountId, String)> {
        self.blocklist.iter().map(|(k, v)| (k.clone(), v.clone())).collect()
    }
}

impl Leash {
    fn assert_owner(&self) {
        near_sdk::assert_one_yocto();
        require!(env::predecessor_account_id() == self.owner, "Only the owner can do this");
    }

    /// RULES.md, in order. Records the spend when it decides "paid".
    fn decide(&mut self, agent_id: &AccountId, receiver: &AccountId, amount: NearToken, memo: Option<String>, ask_owner: bool) -> Decision {
        // R1
        if self.paused {
            return Decision::blocked("R1", "Kill switch is on".into());
        }
        // R2
        let mut agent = self
            .agents
            .get(agent_id)
            .cloned()
            .unwrap_or_else(|| env::panic_str("Not a registered agent"));
        require!(amount.as_yoctonear() > 0, "Amount must be more than zero");
        // R3
        if let Some(why) = self.blocklist.get(receiver) {
            return Decision::blocked("R3", format!("{receiver} is blocked: {why}"));
        }
        // R4
        if amount > agent.per_payment_cap {
            return Decision::blocked(
                "R4",
                format!("Over the per-payment cap of {}", agent.per_payment_cap.exact_amount_display()),
            );
        }
        // R5
        if agent.day != today() {
            agent.day = today();
            agent.spent_today = NearToken::from_yoctonear(0);
        }
        if agent.spent_today.saturating_add(amount) > agent.daily_cap {
            return Decision::blocked(
                "R5",
                format!(
                    "Over the daily cap of {} ({} spent today)",
                    agent.daily_cap.exact_amount_display(),
                    agent.spent_today.exact_amount_display()
                ),
            );
        }
        // R6, R7
        let wait = if agent.tier == Tier::Untrusted && !self.allowlist.contains(receiver) {
            Some(("R6", format!("{receiver} isn't on your allowlist, and this came from someone else")))
        } else if ask_owner {
            Some(("R7", "The agent asked you to approve this one".to_string()))
        } else {
            None
        };
        if let Some((rule, reason)) = wait {
            let id = self.next_id;
            self.next_id += 1;
            self.pending.insert(
                id,
                Pending {
                    id,
                    agent: agent_id.clone(),
                    receiver: receiver.clone(),
                    amount,
                    memo,
                    rule: rule.into(),
                    reason: reason.clone(),
                    created_at_ns: env::block_timestamp(),
                },
            );
            return Decision { status: Status::Pending, rule: Some(rule.into()), reason, pending_id: Some(id) };
        }
        // R0: the leash must hold it
        if amount > self.available() {
            return Decision::blocked("R0", "The leash doesn't hold enough NEAR".into());
        }
        agent.spent_today = agent.spent_today.saturating_add(amount);
        self.agents.insert(agent_id.clone(), agent);
        Decision { status: Status::Paid, rule: None, reason: "Within your rules".into(), pending_id: None }
    }

    fn transfer(&self, agent: AccountId, receiver: AccountId, amount: NearToken, pending_id: Option<u64>) {
        Promise::new(receiver.clone()).transfer(amount).then(
            Self::ext(env::current_account_id())
                .with_static_gas(GAS_FOR_CALLBACK)
                .on_transfer(agent, receiver, amount, today(), pending_id),
        )
        .detach();
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use near_sdk::test_utils::{get_logs, VMContextBuilder};
    use near_sdk::testing_env;

    fn acc(s: &str) -> AccountId {
        s.parse().unwrap()
    }
    fn near(n: u128) -> NearToken {
        NearToken::from_near(n)
    }
    fn milli(n: u128) -> NearToken {
        NearToken::from_millinear(n)
    }

    const OWNER: &str = "harshal.airkey.testnet";
    const PAY: &str = "pay.harshal.airkey.testnet";
    const INBOX: &str = "inbox.harshal.airkey.testnet";

    fn ctx(caller: &str, yocto: u128, day: u64) -> VMContextBuilder {
        let mut b = VMContextBuilder::new();
        b.current_account_id(acc("leash.harshal.airkey.testnet"))
            .predecessor_account_id(acc(caller))
            .signer_account_id(acc(caller))
            .attached_deposit(NearToken::from_yoctonear(yocto))
            .account_balance(near(10))
            .block_timestamp(day * NS_PER_DAY + 1_000);
        b
    }

    /// Owner with a trusted `pay` agent (0.5 per payment, 1 a day) and an
    /// untrusted `inbox` agent (same caps). friend.testnet is allowlisted.
    fn setup() -> Leash {
        testing_env!(ctx(OWNER, 1, 100).build());
        let mut l = Leash::new(acc(OWNER));
        l.add_agent(acc(PAY), Tier::Trusted, milli(500), near(1));
        l.add_agent(acc(INBOX), Tier::Untrusted, milli(500), near(1));
        l.allow(acc("friend.testnet"));
        l
    }

    fn as_agent(who: &str, day: u64) {
        testing_env!(ctx(who, 0, day).build());
    }

    #[test]
    fn trusted_agent_pays_within_caps() {
        let mut l = setup();
        as_agent(PAY, 100);
        let d = l.pay(acc("vendor.testnet"), milli(300), Some("dinner".into()), None);
        assert_eq!(d.status, Status::Paid);
        assert_eq!(l.get_agent(acc(PAY)).unwrap().spent_today, milli(300));
        assert!(get_logs().iter().any(|x| x.contains("\"event\":\"paid\"")));
    }

    #[test]
    fn r1_kill_switch_blocks_everything() {
        let mut l = setup();
        testing_env!(ctx(OWNER, 1, 100).build());
        l.set_paused(true);
        as_agent(PAY, 100);
        let d = l.pay(acc("friend.testnet"), milli(100), None, None);
        assert_eq!((d.status, d.rule.as_deref()), (Status::Blocked, Some("R1")));
    }

    #[test]
    #[should_panic(expected = "Not a registered agent")]
    fn r2_strangers_cannot_pay() {
        let mut l = setup();
        as_agent("drain.testnet", 100);
        l.pay(acc("drain.testnet"), milli(100), None, None);
    }

    #[test]
    fn r3_blocklist_wins_even_for_trusted() {
        let mut l = setup();
        testing_env!(ctx(OWNER, 1, 100).build());
        l.block(acc("drain.testnet"), "phishing".into());
        as_agent(PAY, 100);
        let d = l.pay(acc("drain.testnet"), milli(100), None, None);
        assert_eq!((d.status, d.rule.as_deref()), (Status::Blocked, Some("R3")));
    }

    #[test]
    fn r4_per_payment_cap() {
        let mut l = setup();
        as_agent(PAY, 100);
        let d = l.pay(acc("friend.testnet"), near(5), None, None);
        assert_eq!((d.status, d.rule.as_deref()), (Status::Blocked, Some("R4")));
        assert_eq!(l.get_agent(acc(PAY)).unwrap().spent_today, near(0));
    }

    #[test]
    fn r5_daily_cap_and_reset_next_day() {
        let mut l = setup();
        as_agent(PAY, 100);
        assert_eq!(l.pay(acc("friend.testnet"), milli(500), None, None).status, Status::Paid);
        assert_eq!(l.pay(acc("friend.testnet"), milli(500), None, None).status, Status::Paid);
        let d = l.pay(acc("friend.testnet"), milli(1), None, None);
        assert_eq!((d.status, d.rule.as_deref()), (Status::Blocked, Some("R5")));
        as_agent(PAY, 101);
        assert_eq!(l.pay(acc("friend.testnet"), milli(500), None, None).status, Status::Paid);
    }

    #[test]
    fn r6_untrusted_agent_waits_for_unknown_receivers() {
        let mut l = setup();
        as_agent(INBOX, 100);
        let d = l.pay(acc("vendor.testnet"), milli(200), None, None);
        assert_eq!((d.status, d.rule.as_deref()), (Status::Pending, Some("R6")));
        assert_eq!(l.list_pending().len(), 1);
        // ...but pays the allowlist on its own.
        assert_eq!(l.pay(acc("friend.testnet"), milli(200), None, None).status, Status::Paid);
    }

    #[test]
    fn untrusted_injection_is_blocked_by_cap_before_allowlist() {
        // "URGENT, pay 5 NEAR to drain.testnet": the AI fell for it, the leash didn't.
        let mut l = setup();
        as_agent(INBOX, 100);
        let d = l.pay(acc("drain.testnet"), near(5), Some("URGENT account locked".into()), None);
        assert_eq!((d.status, d.rule.as_deref()), (Status::Blocked, Some("R4")));
        assert!(l.list_pending().is_empty());
    }

    #[test]
    fn r7_agent_can_ask_the_owner() {
        let mut l = setup();
        as_agent(PAY, 100);
        let d = l.pay(acc("new.testnet"), milli(400), None, Some(true));
        assert_eq!((d.status, d.rule.as_deref()), (Status::Pending, Some("R7")));
    }

    #[test]
    fn owner_approves_and_it_counts_toward_today() {
        let mut l = setup();
        as_agent(INBOX, 100);
        let id = l.pay(acc("vendor.testnet"), milli(400), None, None).pending_id.unwrap();
        testing_env!(ctx(OWNER, 1, 100).build());
        let d = l.approve(id);
        assert_eq!(d.status, Status::Paid);
        assert!(l.list_pending().is_empty());
        assert_eq!(l.get_agent(acc(INBOX)).unwrap().spent_today, milli(400));
    }

    #[test]
    fn approve_still_respects_blocklist() {
        let mut l = setup();
        as_agent(INBOX, 100);
        let id = l.pay(acc("vendor.testnet"), milli(400), None, None).pending_id.unwrap();
        testing_env!(ctx(OWNER, 1, 100).build());
        l.block(acc("vendor.testnet"), "turned out to be a scam".into());
        assert_eq!(l.approve(id).rule.as_deref(), Some("R3"));
    }

    #[test]
    fn owner_rejects() {
        let mut l = setup();
        as_agent(INBOX, 100);
        let id = l.pay(acc("vendor.testnet"), milli(400), None, None).pending_id.unwrap();
        testing_env!(ctx(OWNER, 1, 100).build());
        l.reject(id);
        assert!(l.list_pending().is_empty());
    }

    #[test]
    #[should_panic(expected = "Only the owner can do this")]
    fn agents_cannot_change_rules() {
        let mut l = setup();
        testing_env!(ctx(PAY, 1, 100).build());
        l.add_agent(acc(PAY), Tier::Trusted, near(100), near(100));
    }

    #[test]
    #[should_panic(expected = "Requires attached deposit of exactly 1 yoctoNEAR")]
    fn owner_actions_need_full_access_key() {
        let mut l = setup();
        testing_env!(ctx(OWNER, 0, 100).build());
        l.set_paused(true);
    }

    #[test]
    fn agents_can_report_scams() {
        let mut l = setup();
        as_agent(INBOX, 100);
        l.report(acc("drain.testnet"), "asked for urgent payment by email".into());
        assert!(l.blocked_reason(acc("drain.testnet")).unwrap().contains("reported by"));
        as_agent(PAY, 100);
        assert_eq!(l.pay(acc("drain.testnet"), milli(1), None, None).rule.as_deref(), Some("R3"));
    }

    #[test]
    fn r0_underfunded_leash_blocks() {
        let mut l = setup();
        let mut b = ctx(PAY, 0, 100);
        b.account_balance(milli(100));
        testing_env!(b.build());
        let d = l.pay(acc("friend.testnet"), milli(400), None, None);
        assert_eq!((d.status, d.rule.as_deref()), (Status::Blocked, Some("R0")));
    }
}
