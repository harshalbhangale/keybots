//! The contract's methods, on NEAR's host functions directly.

use crate::json::{field, parse_u128, push_str, quoted, u128_str};
use crate::rules::{decide, refund};
use crate::state::{valid_account, State};
use alloc::string::String;
use alloc::vec::Vec;
use core::alloc::{GlobalAlloc, Layout};

#[allow(dead_code)]
mod sys {
    extern "C" {
        pub fn read_register(register_id: u64, ptr: u64);
        pub fn register_len(register_id: u64) -> u64;
        pub fn current_account_id(register_id: u64);
        pub fn predecessor_account_id(register_id: u64);
        pub fn input(register_id: u64);
        pub fn block_timestamp() -> u64;
        pub fn account_balance(balance_ptr: u64);
        pub fn attached_deposit(balance_ptr: u64);
        pub fn storage_usage() -> u64;
        pub fn value_return(value_len: u64, value_ptr: u64);
        pub fn panic_utf8(len: u64, ptr: u64) -> !;
        pub fn log_utf8(len: u64, ptr: u64);
        pub fn storage_write(key_len: u64, key_ptr: u64, value_len: u64, value_ptr: u64, register_id: u64) -> u64;
        pub fn storage_read(key_len: u64, key_ptr: u64, register_id: u64) -> u64;
        pub fn promise_batch_create(account_id_len: u64, account_id_ptr: u64) -> u64;
        pub fn promise_batch_action_transfer(promise_index: u64, amount_ptr: u64);
        pub fn promise_then(
            promise_index: u64,
            account_id_len: u64,
            account_id_ptr: u64,
            function_name_len: u64,
            function_name_ptr: u64,
            arguments_len: u64,
            arguments_ptr: u64,
            amount_ptr: u64,
            gas: u64,
        ) -> u64;
        pub fn promise_return(promise_id: u64);
        pub fn promise_result(result_idx: u64, register_id: u64) -> u64;
    }
}

// ---------- memory: a bump allocator; each call is a fresh instance ----------

struct Bump;
static mut NEXT: usize = 0;
static mut END: usize = 0;

unsafe impl GlobalAlloc for Bump {
    unsafe fn alloc(&self, l: Layout) -> *mut u8 {
        let (size, align) = (l.size(), l.align());
        let mut start = (NEXT + align - 1) & !(align - 1);
        if NEXT == 0 || start + size > END {
            let pages = (size + align + 65_535) / 65_536;
            let old = core::arch::wasm32::memory_grow(0, pages);
            if old == usize::MAX {
                return core::ptr::null_mut();
            }
            let base = old * 65_536;
            start = (base + align - 1) & !(align - 1);
            END = base + pages * 65_536;
        }
        NEXT = start + size;
        start as *mut u8
    }
    unsafe fn dealloc(&self, _: *mut u8, _: Layout) {}
}

#[global_allocator]
static ALLOC: Bump = Bump;

#[panic_handler]
fn on_panic(_: &core::panic::PanicInfo) -> ! {
    fail("Spend Limits Lite stopped")
}

// ---------- host helpers ----------

const STATE: &[u8] = b"s";
const NS_PER_DAY: u64 = 86_400_000_000_000;
/// NEAR's storage price: 10^19 yoctoNEAR a byte (0.01 NEAR a KB).
const BYTE_COST: u128 = 10_000_000_000_000_000_000;
const CALLBACK_GAS: u64 = 10_000_000_000_000;
const MAX_MEMO: usize = 140;

fn fail(msg: &str) -> ! {
    unsafe { sys::panic_utf8(msg.len() as u64, msg.as_ptr() as u64) }
}

fn register(id: u64) -> Vec<u8> {
    unsafe {
        let len = sys::register_len(id);
        if len == u64::MAX {
            return Vec::new();
        }
        let mut buf = alloc::vec![0u8; len as usize];
        sys::read_register(id, buf.as_mut_ptr() as u64);
        buf
    }
}

fn text(v: Vec<u8>) -> String {
    String::from_utf8(v).unwrap_or_default()
}

fn input() -> Vec<u8> {
    unsafe { sys::input(0) };
    let v = register(0);
    if v.is_empty() {
        b"{}".to_vec()
    } else {
        v
    }
}

fn predecessor() -> String {
    unsafe { sys::predecessor_account_id(0) };
    text(register(0))
}

fn me() -> String {
    unsafe { sys::current_account_id(0) };
    text(register(0))
}

fn today() -> u64 {
    unsafe { sys::block_timestamp() / NS_PER_DAY }
}

fn deposit() -> u128 {
    let mut b = [0u8; 16];
    unsafe { sys::attached_deposit(b.as_mut_ptr() as u64) };
    u128::from_le_bytes(b)
}

fn available_now() -> u128 {
    let mut b = [0u8; 16];
    unsafe { sys::account_balance(b.as_mut_ptr() as u64) };
    let locked = BYTE_COST.saturating_mul(unsafe { sys::storage_usage() } as u128);
    u128::from_le_bytes(b).saturating_sub(locked)
}

fn ret(s: &str) {
    unsafe { sys::value_return(s.len() as u64, s.as_ptr() as u64) }
}

fn log(s: &str) {
    unsafe { sys::log_utf8(s.len() as u64, s.as_ptr() as u64) }
}

/// A NEP-297 event with the full contract's standard name, so explorers and the server read both alike.
fn emit(event: &str, data: &str) {
    let mut s = String::from("EVENT_JSON:{\"standard\":\"airkey\",\"version\":\"1.0.0\",\"event\":");
    push_str(&mut s, event);
    s.push_str(",\"data\":[");
    s.push_str(data);
    s.push_str("]}");
    log(&s);
}

fn load() -> State {
    let found = unsafe { sys::storage_read(STATE.len() as u64, STATE.as_ptr() as u64, 0) };
    if found != 1 {
        fail("Spend Limits Lite isn't set up yet");
    }
    State::decode(&text(register(0))).unwrap_or_else(|| fail("Unreadable state"))
}

fn save(st: &State) {
    let s = st.encode();
    unsafe { sys::storage_write(STATE.len() as u64, STATE.as_ptr() as u64, s.len() as u64, s.as_ptr() as u64, 1) };
}

fn arg(inp: &[u8], key: &str) -> Option<String> {
    field(inp, key).filter(|v| v != "null")
}

fn need(inp: &[u8], key: &str) -> String {
    arg(inp, key).unwrap_or_else(|| fail("A required argument is missing"))
}

fn account(inp: &[u8], key: &str) -> String {
    let a = need(inp, key);
    if !valid_account(&a) {
        fail("Not a NEAR account id");
    }
    a
}

fn yocto(inp: &[u8], key: &str) -> u128 {
    parse_u128(&need(inp, key)).unwrap_or_else(|| fail("Amounts are yoctoNEAR, as a string of digits"))
}

/// Owner methods need the owner's full-access key: 1 yoctoNEAR attached, like the full contract.
fn owner_only() -> State {
    if deposit() != 1 {
        fail("Requires attached deposit of exactly 1 yoctoNEAR");
    }
    let st = load();
    if predecessor() != st.owner {
        fail("Only the owner can do this");
    }
    st
}

fn send(to: &str, amount: u128) -> u64 {
    unsafe {
        let p = sys::promise_batch_create(to.len() as u64, to.as_ptr() as u64);
        let a = amount.to_le_bytes();
        sys::promise_batch_action_transfer(p, a.as_ptr() as u64);
        p
    }
}

fn kv(s: &mut String, key: &str, value: &str) {
    if s.len() > 1 {
        s.push(',');
    }
    push_str(s, key);
    s.push(':');
    s.push_str(value);
}

// ---------- set up and money in ----------

/// `new({owner})`: once, by the owner it names or by the contract itself.
#[no_mangle]
pub extern "C" fn new() {
    let found = unsafe { sys::storage_read(STATE.len() as u64, STATE.as_ptr() as u64, 0) };
    if found == 1 {
        fail("Already set up");
    }
    let inp = input();
    let owner = account(&inp, "owner");
    let by = predecessor();
    if by != owner && by != me() {
        fail("Only the owner can set this up");
    }
    save(&State::new(&owner));
}

/// Anyone can top it up.
#[no_mangle]
pub extern "C" fn fund() {
    let mut d = String::from("{");
    kv(&mut d, "by", &quoted(&predecessor()));
    kv(&mut d, "amount", &quoted(&u128_str(deposit())));
    d.push('}');
    emit("funded", &d);
}

// ---------- the agent's side ----------

/// `pay({receiver, amount, memo?, ask_owner?})`, by a registered agent.
#[no_mangle]
pub extern "C" fn pay() {
    let inp = input();
    let receiver = account(&inp, "receiver");
    let amount = yocto(&inp, "amount");
    let memo: Option<String> = arg(&inp, "memo").map(|m| m.chars().take(MAX_MEMO).collect());
    let ask_owner = arg(&inp, "ask_owner").as_deref() == Some("true");
    let agent = predecessor();
    let day = today();
    let mut st = load();
    let d = decide(&mut st, &agent, &receiver, amount, ask_owner, day, available_now()).unwrap_or_else(|e| fail(e));

    let mut data = String::from("{");
    kv(&mut data, "agent", &quoted(&agent));
    kv(&mut data, "receiver", &quoted(&receiver));
    kv(&mut data, "amount", &quoted(&u128_str(amount)));
    kv(&mut data, "memo", &memo.as_deref().map(quoted).unwrap_or_else(|| String::from("null")));
    if d.paid {
        data.push('}');
        save(&st);
        emit("paid", &data);
        let p = send(&receiver, amount);
        let mut cb = String::from("{");
        kv(&mut cb, "agent", &quoted(&agent));
        kv(&mut cb, "receiver", &quoted(&receiver));
        kv(&mut cb, "amount", &quoted(&u128_str(amount)));
        kv(&mut cb, "day", &u128_str(day as u128));
        cb.push('}');
        let me = me();
        let name = "on_transfer";
        let zero = 0u128.to_le_bytes();
        unsafe {
            sys::promise_then(
                p,
                me.len() as u64,
                me.as_ptr() as u64,
                name.len() as u64,
                name.as_ptr() as u64,
                cb.len() as u64,
                cb.as_ptr() as u64,
                zero.as_ptr() as u64,
                CALLBACK_GAS,
            );
        }
    } else {
        kv(&mut data, "rule", &d.rule.map(quoted).unwrap_or_else(|| String::from("null")));
        kv(&mut data, "reason", &quoted(&d.reason));
        data.push('}');
        emit("blocked", &data);
    }
    ret(&d.json());
}

/// Gives the spend back if the transfer failed (an account that doesn't exist, say).
#[no_mangle]
pub extern "C" fn on_transfer() {
    if predecessor() != me() {
        fail("Method on_transfer is private");
    }
    let ok = unsafe { sys::promise_result(0, 0) } == 1;
    if !ok {
        let inp = input();
        let agent = need(&inp, "agent");
        let amount = yocto(&inp, "amount");
        let day = crate::json::parse_u64(&need(&inp, "day")).unwrap_or(0);
        let mut st = load();
        refund(&mut st, &agent, amount, day);
        save(&st);
        let mut d = String::from("{");
        kv(&mut d, "agent", &quoted(&agent));
        kv(&mut d, "receiver", &quoted(&need(&inp, "receiver")));
        kv(&mut d, "amount", &quoted(&u128_str(amount)));
        kv(&mut d, "pending_id", "null");
        d.push('}');
        emit("transfer_failed", &d);
    }
    ret(if ok { "true" } else { "false" });
}

// ---------- the owner's side ----------

/// `add_agent({agent, tier: "trusted"|"untrusted", per_payment_cap, daily_cap})`.
#[no_mangle]
pub extern "C" fn add_agent() {
    let mut st = owner_only();
    let inp = input();
    let agent = account(&inp, "agent");
    let tier = need(&inp, "tier");
    let trusted = match tier.as_str() {
        "trusted" => true,
        "untrusted" => false,
        _ => fail("tier is trusted or untrusted"),
    };
    let per = yocto(&inp, "per_payment_cap");
    let daily = yocto(&inp, "daily_cap");
    if per > daily {
        fail("per_payment_cap must not exceed daily_cap");
    }
    st.set_agent(&agent, trusted, per, daily, today());
    save(&st);
    let mut d = String::from("{");
    kv(&mut d, "agent", &quoted(&agent));
    kv(&mut d, "tier", &quoted(&tier));
    kv(&mut d, "per_payment_cap", &quoted(&u128_str(per)));
    kv(&mut d, "daily_cap", &quoted(&u128_str(daily)));
    d.push('}');
    emit("agent_set", &d);
}

fn one_account(method_event: &str, key: &str, change: fn(&mut State, &str)) {
    let mut st = owner_only();
    let inp = input();
    let a = account(&inp, key);
    change(&mut st, &a);
    save(&st);
    let mut d = String::from("{");
    kv(&mut d, key, &quoted(&a));
    d.push('}');
    emit(method_event, &d);
}

#[no_mangle]
pub extern "C" fn remove_agent() {
    one_account("agent_removed", "agent", |s, a| s.remove_agent(a));
}

#[no_mangle]
pub extern "C" fn allow() {
    one_account("allowed", "account", |s, a| s.allow(a));
}

#[no_mangle]
pub extern "C" fn disallow() {
    one_account("disallowed", "account", |s, a| s.disallow(a));
}

#[no_mangle]
pub extern "C" fn unblock() {
    one_account("unblocked_account", "account", |s, a| s.unblock(a));
}

/// `block({account, reason})`.
#[no_mangle]
pub extern "C" fn block() {
    let mut st = owner_only();
    let inp = input();
    let a = account(&inp, "account");
    let reason = arg(&inp, "reason").unwrap_or_default();
    st.block(&a, &reason);
    save(&st);
    let mut d = String::from("{");
    kv(&mut d, "account", &quoted(&a));
    kv(&mut d, "reason", &quoted(st.blocked_reason(&a).unwrap_or("")));
    d.push('}');
    emit("blocked_account", &d);
}

/// Stop everything: `set_paused({paused})`.
#[no_mangle]
pub extern "C" fn set_paused() {
    let mut st = owner_only();
    let paused = need(&input(), "paused") == "true";
    st.paused = paused;
    save(&st);
    emit(if paused { "paused" } else { "resumed" }, "{}");
}

/// `withdraw({amount})`: back to the owner, never more than is free.
#[no_mangle]
pub extern "C" fn withdraw() {
    let st = owner_only();
    let amount = yocto(&input(), "amount");
    if amount > available_now() {
        fail("Not enough available NEAR");
    }
    let mut d = String::from("{");
    kv(&mut d, "amount", &quoted(&u128_str(amount)));
    d.push('}');
    emit("withdrawn", &d);
    let p = send(&st.owner, amount);
    unsafe { sys::promise_return(p) };
}

// ---------- views (the same names and shapes as the full contract) ----------

#[no_mangle]
pub extern "C" fn get_owner() {
    ret(&quoted(&load().owner));
}

#[no_mangle]
pub extern "C" fn is_paused() {
    ret(if load().paused { "true" } else { "false" });
}

#[no_mangle]
pub extern "C" fn available() {
    ret(&quoted(&u128_str(available_now())));
}

#[no_mangle]
pub extern "C" fn list_agents() {
    ret(&load().agents_json());
}

#[no_mangle]
pub extern "C" fn get_agent() {
    let a = need(&input(), "agent");
    match load().agents.iter().find(|x| x.account == a) {
        Some(x) => ret(&crate::state::agent_json(x)),
        None => ret("null"),
    }
}

#[no_mangle]
pub extern "C" fn list_allowed() {
    ret(&load().allowed_json());
}

#[no_mangle]
pub extern "C" fn list_blocked() {
    ret(&load().blocked_json());
}

/// Lite has no approvals, so nothing ever waits.
#[no_mangle]
pub extern "C" fn list_pending() {
    ret("[]");
}

#[no_mangle]
pub extern "C" fn is_allowed() {
    let a = need(&input(), "account");
    ret(if load().is_allowed(&a) { "true" } else { "false" });
}

#[no_mangle]
pub extern "C" fn blocked_reason() {
    let a = need(&input(), "account");
    match load().blocked_reason(&a) {
        Some(r) => ret(&quoted(r)),
        None => ret("null"),
    }
}

/// Lite never lets agents sell tokens.
#[no_mangle]
pub extern "C" fn get_token_cap() {
    ret("null");
}

/// What this contract is, for anyone checking: `{"name","rules"}`.
#[no_mangle]
pub extern "C" fn contract_info() {
    let mut s = String::from("{");
    kv(&mut s, "name", &quoted("Spend Limits Lite"));
    kv(&mut s, "rules", &quoted("R1 Stop everything, R2 agents only, R3 blocked list, R4 per payment, R5 daily, R6 allowed list for the untrusted agent, R7 no approvals, R0 balance"));
    s.push('}');
    ret(&s);
}
