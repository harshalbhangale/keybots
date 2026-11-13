export const REPO = "https://github.com/harshalbhangale/near-hack";
export const LEASH = "https://testnet.nearblocks.io/address/leash.airkey-harshal.testnet";
export const E2E = `${REPO}/blob/main/docs/evidence/testnet-e2e.md`;
// Placeholder until the AIRKEY Android build is uploaded: swap this one URL for the AIRKEY APK on S3.
export const APK_URL = "https://kall-markets-downloads-308324916322.s3.ap-south-1.amazonaws.com/apps/kall-keyboard.apk";

export function GitHub({ size = 22 }: { size?: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 16 16" fill="currentColor" aria-hidden>
      <path d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.013 8.013 0 0016 8c0-4.42-3.58-8-8-8z" />
    </svg>
  );
}

export function Android({ size = 22 }: { size?: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="currentColor" aria-hidden>
      <path d="M17.6 9.48l1.84-3.18a.38.38 0 00-.66-.38l-1.87 3.23a11.4 11.4 0 00-9.82 0L5.22 5.92a.38.38 0 10-.66.38L6.4 9.48A10.78 10.78 0 001 18h22a10.78 10.78 0 00-5.4-8.52zM7 15.25a1.25 1.25 0 111.25-1.25A1.25 1.25 0 017 15.25zm10 0A1.25 1.25 0 1118.25 14 1.25 1.25 0 0117 15.25z" />
    </svg>
  );
}

export function Apple({ size = 22 }: { size?: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="currentColor" aria-hidden>
      <path d="M17.05 12.53c-.03-2.9 2.37-4.29 2.48-4.36-1.35-1.97-3.45-2.24-4.2-2.27-1.79-.18-3.49 1.05-4.4 1.05-.9 0-2.3-1.02-3.79-1-1.95.03-3.74 1.13-4.74 2.87-2.02 3.5-.52 8.68 1.45 11.52.96 1.39 2.11 2.95 3.62 2.9 1.45-.06 2-.94 3.76-.94s2.25.94 3.79.91c1.56-.03 2.55-1.42 3.51-2.82 1.1-1.62 1.56-3.19 1.58-3.27-.03-.02-3.03-1.16-3.06-4.59zM14.16 4c.8-.97 1.34-2.32 1.19-3.66-1.15.05-2.55.77-3.38 1.73-.74.86-1.39 2.23-1.22 3.55 1.29.1 2.6-.65 3.41-1.62z" />
    </svg>
  );
}

export function Play({ size = 22 }: { size?: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="currentColor" aria-hidden>
      <path d="M3.6 1.8c-.36.38-.6.97-.6 1.73v16.94c0 .76.24 1.35.6 1.73l.1.09 9.49-9.49v-.22L3.7 1.71l-.1.09z" />
      <path d="M16.35 15.95l-3.16-3.16v-.22l3.16-3.16.07.04 3.75 2.13c1.07.6 1.07 1.6 0 2.21l-3.75 2.12-.07.04z" opacity=".75" />
      <path d="M16.42 15.9L13.19 12.7 3.6 22.2c.35.37.93.42 1.59.05l11.23-6.35z" opacity=".55" />
      <path d="M16.42 8.1L5.19 1.75C4.53 1.38 3.95 1.43 3.6 1.8l9.59 9.5 3.23-3.2z" opacity=".9" />
    </svg>
  );
}

/** The AIRKEY logo: a lime keycap with the NEAR mark as its legend (public/logo.svg). */
export function Mark({ size = 28 }: { size?: number }) {
  return <img src="/logo.svg" width={size} height={size} alt="" aria-hidden style={{ display: "block" }} />;
}

/** Android download, App Store and Google Play (soon), GitHub. */
export function Downloads() {
  return (
    <div className="stores-wrap">
      <div className="stores">
        <a className="store primary" href={APK_URL} download>
          <Android />
          <span className="store-lines">
            <small>Download today</small>
            <b>Android APK</b>
          </span>
        </a>
        <a className="store" href={REPO} target="_blank" rel="noreferrer">
          <GitHub />
          <span className="store-lines">
            <small>Open source, live on</small>
            <b>GitHub</b>
          </span>
        </a>
      </div>
      <div className="stores soon-row" aria-label="Coming soon to the App Store and Google Play">
        <span className="store soon" aria-disabled="true">
          <Apple size={18} />
          <span className="store-lines">
            <small>Coming soon on</small>
            <b>App Store</b>
          </span>
        </span>
        <span className="store soon" aria-disabled="true">
          <Play size={18} />
          <span className="store-lines">
            <small>Coming soon on</small>
            <b>Google Play</b>
          </span>
        </span>
      </div>
    </div>
  );
}
