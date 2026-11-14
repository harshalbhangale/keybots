//! The spending rules, in the full contract's order and with its rule ids
//! (see contracts/leash/RULES.md). Lite has no approvals, so what the full
//! contract would hold for the owner (R6, R7) is stopped here instead.

use crate::json::{near, push_str};
use crate::state::State;
use alloc::string::String;

#[derive(Debug, PartialEq)]
pub struct Decision {
    pub paid: bool,
    pub rule: Option<&'static str>,
    pub reason: String,
}

impl Decision {
    fn blocked(rule: &'static str, reason: String) -> Self {
        Decision { paid: false, rule: Some(rule), reason }
    }

    /// Shaped like the full contract's Decision; `pending_id` is always null.
    pub fn json(&self) -> String {
        let mut s = String::from("{\"status\":");
        s.push_str(if self.paid { "\"paid\"" } else { "\"blocked\"" });
        s.push_str(",\"rule\":");
        match self.rule {
            Some(r) => push_str(&mut s, r),
            None => s.push_str("null"),
        }
        s.push_str(",\"reason\":");
        push_str(&mut s, &self.reason);
        s.push_str(",\"pending_id\":null}");
        s
    }
}

/// What the contract does when an agent that isn't registered calls `pay`.
pub const NOT_AN_AGENT: &str = "Not a registered agent";
pub const ZERO: &str = "Amount must be more than zero";

/// Decide one payment. On "paid" the spend is recorded in `st`; the caller
/// saves it and sends the NEAR. `Err` means the call should fail outright.
pub fn decide(st: &mut State, agent: &str, receiver: &str, amount: u128, ask_owner: bool, today: u64, available: u128) -> Result<Decision, &'static str> {
    // R1
    if st.paused {
        return Ok(Decision::blocked("R1", "Kill switch is on".into()));
    }
    // R2
    let blocked_why = st.blocked_reason(receiver).map(String::from);
    let allowed = st.is_allowed(receiver);
    let a = st.agent_mut(agent).ok_or(NOT_AN_AGENT)?;
    if amount == 0 {
        return Err(ZERO);
    }
    // R3
    if let Some(why) = blocked_why {
        let mut r = String::from(receiver);
        r.push_str(" is blocked: ");
        r.push_str(&why);
        return Ok(Decision::blocked("R3", r));
    }
    // R4
    if amount > a.per_payment_cap {
        let mut r = String::from("Over the per-payment cap of ");
        r.push_str(&near(a.per_payment_cap));
        return Ok(Decision::blocked("R4", r));
    }
    // R5
    let spent = if a.day == today { a.spent_today } else { 0 };
    if spent.saturating_add(amount) > a.daily_cap {
        let mut r = String::from("Over the daily cap of ");
        r.push_str(&near(a.daily_cap));
        r.push_str(" (");
        r.push_str(&near(spent));
        r.push_str(" spent today)");
        return Ok(Decision::blocked("R5", r));
    }
    // R6: Lite can't hold a payment for the owner, so it stops it.
    if !a.trusted && !allowed {
        let mut r = String::from(receiver);
        r.push_str(" isn't on your allowlist, and this came from someone else");
        return Ok(Decision::blocked("R6", r));
    }
    // R7
    if ask_owner {
        return Ok(Decision::blocked("R7", "The agent asked you to approve this one, and Spend Limits Lite has no approvals".into()));
    }
    // R0
    if amount > available {
        return Ok(Decision::blocked("R0", "The leash doesn't hold enough NEAR".into()));
    }
    a.day = today;
    a.spent_today = spent + amount;
    Ok(Decision { paid: true, rule: None, reason: "Within your rules".into() })
}

/// A failed transfer gives the spend back, if it's still the same day.
pub fn refund(st: &mut State, agent: &str, amount: u128, day: u64) {
    if let Some(a) = st.agent_mut(agent) {
        if a.day == day {
            a.spent_today = a.spent_today.saturating_sub(amount);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const N: u128 = 1_000_000_000_000_000_000_000_000;
    const DAY: u64 = 20_400;

    fn state() -> State {
        let mut s = State::new("hellbuddy.near");
        s.set_agent("pay.hellbuddy.near", true, N / 2, N, DAY);
        s.set_agent("inbox.hellbuddy.near", false, N / 10, N / 5, DAY);
        s.allow("friend.near");
        s.block("drain.near", "Scam");
        s
    }

    fn pay(s: &mut State, agent: &str, to: &str, amount: u128) -> Decision {
        decide(s, agent, to, amount, false, DAY, 10 * N).unwrap()
    }

    #[test]
    fn pays_inside_the_rules_and_records_it() {
        let mut s = state();
        let d = pay(&mut s, "pay.hellbuddy.near", "bob.near", N / 5);
        assert!(d.paid);
        assert_eq!(d.json(), r#"{"status":"paid","rule":null,"reason":"Within your rules","pending_id":null}"#);
        assert_eq!(s.agent_mut("pay.hellbuddy.near").unwrap().spent_today, N / 5);
    }

    #[test]
    fn stop_everything_wins() {
        let mut s = state();
        s.paused = true;
        assert_eq!(pay(&mut s, "pay.hellbuddy.near", "bob.near", 1).rule, Some("R1"));
    }

    #[test]
    fn strangers_and_zero_fail_the_call() {
        let mut s = state();
        assert_eq!(decide(&mut s, "evil.near", "bob.near", 1, false, DAY, N), Err(NOT_AN_AGENT));
        assert_eq!(decide(&mut s, "pay.hellbuddy.near", "bob.near", 0, false, DAY, N), Err(ZERO));
    }

    #[test]
    fn blocked_list() {
        let mut s = state();
        let d = pay(&mut s, "pay.hellbuddy.near", "drain.near", 1);
        assert_eq!((d.rule, d.reason.as_str()), (Some("R3"), "drain.near is blocked: Scam"));
    }

    #[test]
    fn per_payment_and_daily_caps() {
        let mut s = state();
        let d = pay(&mut s, "pay.hellbuddy.near", "bob.near", N);
        assert_eq!((d.rule, d.reason.as_str()), (Some("R4"), "Over the per-payment cap of 0.5 NEAR"));
        assert!(pay(&mut s, "pay.hellbuddy.near", "bob.near", N / 2).paid);
        assert!(pay(&mut s, "pay.hellbuddy.near", "bob.near", N / 2).paid);
        let d = pay(&mut s, "pay.hellbuddy.near", "bob.near", 1);
        assert_eq!((d.rule, d.reason.as_str()), (Some("R5"), "Over the daily cap of 1 NEAR (1 NEAR spent today)"));
    }

    #[test]
    fn a_new_day_starts_at_zero() {
        let mut s = state();
        assert!(pay(&mut s, "pay.hellbuddy.near", "bob.near", N / 2).paid);
        assert!(pay(&mut s, "pay.hellbuddy.near", "bob.near", N / 2).paid);
        assert!(decide(&mut s, "pay.hellbuddy.near", "bob.near", N / 2, false, DAY + 1, 10 * N).unwrap().paid);
        assert_eq!(s.agent_mut("pay.hellbuddy.near").unwrap().spent_today, N / 2);
    }

    #[test]
    fn untrusted_only_pays_the_allowed_list() {
        let mut s = state();
        assert_eq!(pay(&mut s, "inbox.hellbuddy.near", "bob.near", 1).rule, Some("R6"));
        assert!(pay(&mut s, "inbox.hellbuddy.near", "friend.near", 1).paid);
    }

    #[test]
    fn asking_the_owner_is_stopped_and_balance_is_checked() {
        let mut s = state();
        assert_eq!(decide(&mut s, "pay.hellbuddy.near", "bob.near", 1, true, DAY, N).unwrap().rule, Some("R7"));
        assert_eq!(decide(&mut s, "pay.hellbuddy.near", "bob.near", N / 2, false, DAY, N / 4).unwrap().rule, Some("R0"));
        assert_eq!(s.agent_mut("pay.hellbuddy.near").unwrap().spent_today, 0);
    }

    #[test]
    fn refund_gives_the_spend_back_the_same_day_only() {
        let mut s = state();
        assert!(pay(&mut s, "pay.hellbuddy.near", "bob.near", N / 2).paid);
        refund(&mut s, "pay.hellbuddy.near", N / 2, DAY - 1);
        assert_eq!(s.agent_mut("pay.hellbuddy.near").unwrap().spent_today, N / 2);
        refund(&mut s, "pay.hellbuddy.near", N / 2, DAY);
        assert_eq!(s.agent_mut("pay.hellbuddy.near").unwrap().spent_today, 0);
    }
}
