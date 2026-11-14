//! Spend Limits Lite: the core of Keybots' Spend Limits contract, small enough
//! for NEAR mainnet on a small budget. Same method names, arguments, return
//! shapes and events as the full contract (contracts/leash), so the Keybots
//! server works with either.
//!
//! Kept: Stop everything (R1), registered agents (R2), the blocked list (R3),
//! per-payment and daily limits (R4, R5), the allowed list for the untrusted
//! agent (R6), the balance check (R0), owner-only changes, withdraw.
//! Left out: swaps, token limits and approvals. A payment the full contract
//! would hold for the owner is stopped here instead.

#![cfg_attr(target_arch = "wasm32", no_std)]

extern crate alloc;

pub mod json;
pub mod rules;
pub mod state;

#[cfg(target_arch = "wasm32")]
mod wasm;
