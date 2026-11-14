//! Just enough JSON: read a flat object's fields, and write strings and numbers.

use alloc::string::String;
use alloc::vec::Vec;

/// The fields of a flat JSON object, in order. Strings come back unescaped,
/// other values (numbers, true, false, null) as their raw text. Nested objects
/// and arrays are refused.
pub fn fields(s: &[u8]) -> Option<Vec<(String, String)>> {
    let mut i = skip_ws(s, 0);
    if *s.get(i)? != b'{' {
        return None;
    }
    i += 1;
    let mut out = Vec::new();
    loop {
        i = skip_ws(s, i);
        match *s.get(i)? {
            b'}' => return Some(out),
            b',' => {
                i += 1;
                continue;
            }
            b'"' => {}
            _ => return None,
        }
        let (k, j) = string(s, i)?;
        i = skip_ws(s, j);
        if *s.get(i)? != b':' {
            return None;
        }
        i = skip_ws(s, i + 1);
        let (v, j) = if *s.get(i)? == b'"' { string(s, i)? } else { raw(s, i)? };
        out.push((k, v));
        i = j;
    }
}

/// One field of a flat JSON object.
pub fn field(s: &[u8], key: &str) -> Option<String> {
    fields(s)?.into_iter().find(|(k, _)| k == key).map(|(_, v)| v)
}

fn skip_ws(s: &[u8], mut i: usize) -> usize {
    while i < s.len() && matches!(s[i], b' ' | b'\n' | b'\r' | b'\t') {
        i += 1;
    }
    i
}

fn raw(s: &[u8], i: usize) -> Option<(String, usize)> {
    if matches!(s[i], b'{' | b'[') {
        return None;
    }
    let mut j = i;
    while j < s.len() && !matches!(s[j], b',' | b'}' | b' ' | b'\n' | b'\r' | b'\t') {
        j += 1;
    }
    if j == i {
        return None;
    }
    Some((String::from(core::str::from_utf8(&s[i..j]).ok()?), j))
}

fn string(s: &[u8], i: usize) -> Option<(String, usize)> {
    let mut out: Vec<u8> = Vec::new();
    let mut j = i + 1;
    loop {
        let c = *s.get(j)?;
        match c {
            b'"' => return Some((String::from_utf8(out).ok()?, j + 1)),
            b'\\' => {
                let e = *s.get(j + 1)?;
                j += 2;
                match e {
                    b'"' => out.push(b'"'),
                    b'\\' => out.push(b'\\'),
                    b'/' => out.push(b'/'),
                    b'n' => out.push(b'\n'),
                    b't' => out.push(b'\t'),
                    b'r' => out.push(b'\r'),
                    b'b' => out.push(8),
                    b'f' => out.push(12),
                    b'u' => {
                        let hex = core::str::from_utf8(s.get(j..j + 4)?).ok()?;
                        let cp = u32::from_str_radix(hex, 16).ok()?;
                        j += 4;
                        let ch = char::from_u32(cp).unwrap_or('\u{FFFD}');
                        let mut buf = [0u8; 4];
                        out.extend_from_slice(ch.encode_utf8(&mut buf).as_bytes());
                    }
                    _ => return None,
                }
            }
            _ => {
                out.push(c);
                j += 1;
            }
        }
    }
}

const HEX: &[u8; 16] = b"0123456789abcdef";

/// `v` as a JSON string, quotes included.
pub fn push_str(out: &mut String, v: &str) {
    out.push('"');
    for ch in v.chars() {
        match ch {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            c if (c as u32) < 0x20 => {
                out.push_str("\\u00");
                out.push(HEX[(c as usize) >> 4] as char);
                out.push(HEX[(c as usize) & 15] as char);
            }
            c => out.push(c),
        }
    }
    out.push('"');
}

pub fn quoted(v: &str) -> String {
    let mut s = String::new();
    push_str(&mut s, v);
    s
}

pub fn u128_str(mut n: u128) -> String {
    if n == 0 {
        return String::from("0");
    }
    let mut b = [0u8; 40];
    let mut i = b.len();
    while n > 0 {
        i -= 1;
        b[i] = b'0' + (n % 10) as u8;
        n /= 10;
    }
    String::from(core::str::from_utf8(&b[i..]).unwrap_or("0"))
}

pub fn parse_u128(s: &str) -> Option<u128> {
    if s.is_empty() || s.len() > 39 {
        return None;
    }
    let mut n: u128 = 0;
    for c in s.bytes() {
        if !c.is_ascii_digit() {
            return None;
        }
        n = n.checked_mul(10)?.checked_add((c - b'0') as u128)?;
    }
    Some(n)
}

pub fn parse_u64(s: &str) -> Option<u64> {
    let n = parse_u128(s)?;
    if n > u64::MAX as u128 {
        None
    } else {
        Some(n as u64)
    }
}

/// 500000000000000000000000 → "0.5 NEAR".
pub fn near(yocto: u128) -> String {
    const ONE: u128 = 1_000_000_000_000_000_000_000_000;
    let mut s = u128_str(yocto / ONE);
    let frac = yocto % ONE;
    if frac > 0 {
        let digits = u128_str(frac + ONE); // "1" then 24 digits, zeros kept
        let digits = digits[1..].trim_end_matches('0');
        s.push('.');
        s.push_str(digits);
    }
    s.push_str(" NEAR");
    s
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_a_flat_object() {
        let f = fields(br#" { "receiver": "bob.near", "amount":"5", "ask_owner": true, "memo": "a \"b\" \u00e9\n", "n": 12 } "#).unwrap();
        assert_eq!(f[0], ("receiver".into(), "bob.near".into()));
        assert_eq!(f[2], ("ask_owner".into(), "true".into()));
        assert_eq!(f[3].1, "a \"b\" é\n");
        assert_eq!(f[4].1, "12");
        assert_eq!(field(br#"{}"#, "x"), None);
    }

    #[test]
    fn refuses_nested_and_broken() {
        assert!(fields(br#"{"a": {"b": 1}}"#).is_none());
        assert!(fields(br#"{"a": [1]}"#).is_none());
        assert!(fields(br#"{"a": "x"#).is_none());
        assert!(fields(b"").is_none());
    }

    #[test]
    fn writes_strings_and_numbers() {
        assert_eq!(quoted("a\"b\\\n\u{1}"), "\"a\\\"b\\\\\\n\\u0001\"");
        assert_eq!(u128_str(0), "0");
        assert_eq!(u128_str(u128::MAX), "340282366920938463463374607431768211455");
        assert_eq!(parse_u128("340282366920938463463374607431768211456"), None);
        assert_eq!(parse_u128("12a"), None);
        assert_eq!(near(500_000_000_000_000_000_000_000), "0.5 NEAR");
        assert_eq!(near(2_000_000_000_000_000_000_000_000), "2 NEAR");
        assert_eq!(near(10_000_000_000_000_000_000_000), "0.01 NEAR");
    }
}
