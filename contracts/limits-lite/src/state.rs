//! The contract's whole state, kept under one storage key as short text lines:
//!
//! ```text
//! o <owner>
//! p 0|1
//! a <agent> t|u <per_payment_cap> <daily_cap> <spent_today> <day>
//! l <allowed account>
//! b <blocked account> <reason, to the end of the line>
//! ```

use crate::json::{parse_u128, parse_u64, push_str, u128_str};
use alloc::string::String;
use alloc::vec::Vec;

#[derive(Clone, Debug, PartialEq)]
pub struct Agent {
    pub account: String,
    /// Trusted acts on what the owner types; untrusted on other people's words.
    pub trusted: bool,
    pub per_payment_cap: u128,
    pub daily_cap: u128,
    pub spent_today: u128,
    pub day: u64,
}

#[derive(Clone, Debug, PartialEq)]
pub struct State {
    pub owner: String,
    pub paused: bool,
    pub agents: Vec<Agent>,
    pub allowed: Vec<String>,
    pub blocked: Vec<(String, String)>,
}

/// Blocked-list reasons are kept to this many characters, like the full contract's.
pub const MAX_REASON: usize = 280;

impl State {
    pub fn new(owner: &str) -> Self {
        State { owner: owner.into(), paused: false, agents: Vec::new(), allowed: Vec::new(), blocked: Vec::new() }
    }

    pub fn encode(&self) -> String {
        let mut s = String::new();
        s.push_str("o ");
        s.push_str(&self.owner);
        s.push_str(if self.paused { "\np 1\n" } else { "\np 0\n" });
        for a in &self.agents {
            s.push_str("a ");
            s.push_str(&a.account);
            s.push_str(if a.trusted { " t " } else { " u " });
            s.push_str(&u128_str(a.per_payment_cap));
            s.push(' ');
            s.push_str(&u128_str(a.daily_cap));
            s.push(' ');
            s.push_str(&u128_str(a.spent_today));
            s.push(' ');
            s.push_str(&u128_str(a.day as u128));
            s.push('\n');
        }
        for l in &self.allowed {
            s.push_str("l ");
            s.push_str(l);
            s.push('\n');
        }
        for (b, why) in &self.blocked {
            s.push_str("b ");
            s.push_str(b);
            s.push(' ');
            s.push_str(&one_line(why));
            s.push('\n');
        }
        s
    }

    pub fn decode(text: &str) -> Option<Self> {
        let mut st = State::new("");
        for line in text.lines() {
            let (tag, rest) = line.split_once(' ')?;
            match tag {
                "o" => st.owner = rest.into(),
                "p" => st.paused = rest == "1",
                "a" => {
                    let mut p = rest.split(' ');
                    st.agents.push(Agent {
                        account: p.next()?.into(),
                        trusted: p.next()? == "t",
                        per_payment_cap: parse_u128(p.next()?)?,
                        daily_cap: parse_u128(p.next()?)?,
                        spent_today: parse_u128(p.next()?)?,
                        day: parse_u64(p.next()?)?,
                    });
                }
                "l" => st.allowed.push(rest.into()),
                "b" => {
                    let (acct, why) = rest.split_once(' ').unwrap_or((rest, ""));
                    st.blocked.push((acct.into(), why.into()));
                }
                _ => return None,
            }
        }
        if st.owner.is_empty() {
            None
        } else {
            Some(st)
        }
    }

    pub fn agent_mut(&mut self, account: &str) -> Option<&mut Agent> {
        self.agents.iter_mut().find(|a| a.account == account)
    }

    pub fn is_allowed(&self, account: &str) -> bool {
        self.allowed.iter().any(|a| a == account)
    }

    pub fn blocked_reason(&self, account: &str) -> Option<&str> {
        self.blocked.iter().find(|(a, _)| a == account).map(|(_, r)| r.as_str())
    }

    pub fn set_agent(&mut self, account: &str, trusted: bool, per_payment_cap: u128, daily_cap: u128, today: u64) {
        match self.agent_mut(account) {
            Some(a) => {
                a.trusted = trusted;
                a.per_payment_cap = per_payment_cap;
                a.daily_cap = daily_cap;
            }
            None => self.agents.push(Agent { account: account.into(), trusted, per_payment_cap, daily_cap, spent_today: 0, day: today }),
        }
    }

    pub fn remove_agent(&mut self, account: &str) {
        self.agents.retain(|a| a.account != account);
    }

    pub fn allow(&mut self, account: &str) {
        if !self.is_allowed(account) {
            self.allowed.push(account.into());
        }
    }

    pub fn disallow(&mut self, account: &str) {
        self.allowed.retain(|a| a != account);
    }

    pub fn block(&mut self, account: &str, reason: &str) {
        let reason: String = one_line(reason).chars().take(MAX_REASON).collect();
        match self.blocked.iter_mut().find(|(a, _)| a == account) {
            Some(b) => b.1 = reason,
            None => self.blocked.push((account.into(), reason)),
        }
    }

    pub fn unblock(&mut self, account: &str) {
        self.blocked.retain(|(a, _)| a != account);
    }

    /// `list_agents`, shaped like the full contract's: [[account, {tier, caps, spent_today, day}], ...].
    pub fn agents_json(&self) -> String {
        let mut s = String::from("[");
        for (i, a) in self.agents.iter().enumerate() {
            if i > 0 {
                s.push(',');
            }
            s.push('[');
            push_str(&mut s, &a.account);
            s.push(',');
            s.push_str(&agent_json(a));
            s.push(']');
        }
        s.push(']');
        s
    }

    pub fn allowed_json(&self) -> String {
        let mut s = String::from("[");
        for (i, a) in self.allowed.iter().enumerate() {
            if i > 0 {
                s.push(',');
            }
            push_str(&mut s, a);
        }
        s.push(']');
        s
    }

    pub fn blocked_json(&self) -> String {
        let mut s = String::from("[");
        for (i, (a, why)) in self.blocked.iter().enumerate() {
            if i > 0 {
                s.push(',');
            }
            s.push('[');
            push_str(&mut s, a);
            s.push(',');
            push_str(&mut s, why);
            s.push(']');
        }
        s.push(']');
        s
    }
}

/// One agent as the full contract shows it: {tier, per_payment_cap, daily_cap, spent_today, day}.
pub fn agent_json(a: &Agent) -> String {
    let mut s = String::from("{\"tier\":");
    s.push_str(if a.trusted { "\"trusted\"" } else { "\"untrusted\"" });
    s.push_str(",\"per_payment_cap\":");
    push_str(&mut s, &u128_str(a.per_payment_cap));
    s.push_str(",\"daily_cap\":");
    push_str(&mut s, &u128_str(a.daily_cap));
    s.push_str(",\"spent_today\":");
    push_str(&mut s, &u128_str(a.spent_today));
    s.push_str(",\"day\":");
    s.push_str(&u128_str(a.day as u128));
    s.push('}');
    s
}

fn one_line(s: &str) -> String {
    s.chars().map(|c| if c == '\n' || c == '\r' { ' ' } else { c }).collect()
}

/// A NEAR account id: 2 to 64 of a-z, 0-9, '-', '_', '.', with no separator at
/// either end or two in a row. (Implicit 64-hex accounts pass too.)
pub fn valid_account(id: &str) -> bool {
    let b = id.as_bytes();
    if b.len() < 2 || b.len() > 64 {
        return false;
    }
    let sep = |c: u8| matches!(c, b'-' | b'_' | b'.');
    let mut prev_sep = true;
    for &c in b {
        let ok = c.is_ascii_lowercase() || c.is_ascii_digit() || sep(c);
        if !ok || (sep(c) && prev_sep) {
            return false;
        }
        prev_sep = sep(c);
    }
    !prev_sep
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn round_trips() {
        let mut s = State::new("hellbuddy.near");
        s.paused = true;
        s.set_agent("pay.hellbuddy.near", true, 5, 10, 20_000);
        s.set_agent("inbox.hellbuddy.near", false, 1, 2, 20_000);
        s.allow("friend.near");
        s.block("drain.near", "scam\nlink");
        let back = State::decode(&s.encode()).unwrap();
        assert_eq!(back, s);
        assert_eq!(back.blocked_reason("drain.near"), Some("scam link"));
    }

    #[test]
    fn json_lists_match_the_full_contract() {
        let mut s = State::new("o.near");
        s.set_agent("pay.o.near", true, 5, 10, 7);
        s.block("x.near", "says \"hi\"");
        assert_eq!(s.agents_json(), r#"[["pay.o.near",{"tier":"trusted","per_payment_cap":"5","daily_cap":"10","spent_today":"0","day":7}]]"#);
        assert_eq!(s.blocked_json(), r#"[["x.near","says \"hi\""]]"#);
        assert_eq!(s.allowed_json(), "[]");
    }

    #[test]
    fn checks_account_ids() {
        assert!(valid_account("hellbuddy.near"));
        assert!(valid_account("pay.hellbuddy.near"));
        assert!(valid_account("a1"));
        assert!(!valid_account("Bob.near"));
        assert!(!valid_account(".near"));
        assert!(!valid_account("a..near"));
        assert!(!valid_account("near."));
        assert!(!valid_account("a b"));
        assert!(!valid_account("x"));
    }
}
