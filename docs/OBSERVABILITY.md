# Observability & Analytics Guide for Trackpad Toggle

This guide explains how observability and traffic monitoring are configured for **Trackpad Toggle** (`trackpad-toggle.rajanraj.me`), covering both client-side interaction monitoring and edge-level AI bot/crawler analysis.

---

## 1. On-Page Live Unique Human Visitor Counter

A live, lightweight visitor counter is displayed in the website footer:
- **API Backend**: Powered by [CounterAPI](https://counterapi.com) and fallback badge parsing via [Hits.sh](https://hits.sh).
- **Bot Filtering**: Automatically detects search engine crawlers (`navigator.webdriver`, bot User-Agents) and bypasses incrementing to count **genuine human visitors only**.
- **Session Deduplication**: Uses `sessionStorage` so refreshing the page or navigating back and forth within the same browser session does not inflate the count.
- **Fail-Safe**: If the API is unreachable or rate-limited, cached counts from `localStorage` are displayed gracefully without breaking page layout or performance.

---

## 2. In-Page Event Tracking & Performance Monitoring

`web/app.js` automatically measures and logs key user interactions and Core Web Vitals:
- **Download Conversions**: Tracks clicks on the `.dmg` download button (`TrackpadToggle.dmg`).
- **Command Copies**: Tracks when users copy the Homebrew Cask or npx commands.
- **Navigation Timing API**: Measures real-world visitor load times:
  - **TTFB (Time to First Byte)**: Server response latency.
  - **DOM Content Loaded**: HTML parsing duration.
  - **Total Page Load**: Full asset render duration.

---

## 3. Recommended Edge Observability Setup (Cloudflare)

To capture **AI crawlers, bots, geographic breakdown, and server response times**, route your domain `trackpad-toggle.rajanraj.me` through Cloudflare (free tier):

### Why Cloudflare Edge Observability?
Because AI search bots (`GPTBot`, `PerplexityBot`, `ClaudeBot`, `Google-Extended`) fetch static Markdown files (`/llms.txt`, `/robots.txt`) and **do not execute JavaScript**, edge-level proxying is the **only way** to measure them.

### Setup Instructions (3 Steps):
1. **Proxy the DNS**:
   - In your Cloudflare dashboard for `rajanraj.me`, ensure the CNAME record for `trackpad-toggle` is set to **Proxied** (orange cloud).
2. **Access Security & Bot Analytics**:
   - Go to **Security → Bots** or **Analytics & Logs → Traffic**:
     - **Automated vs. Human**: Cloudflare automatically classifies requests into Automated (Bots/Crawlers) vs. Humans.
     - **Verified Bots**: Displays specific breakdowns for OpenAI (`GPTBot`), Anthropic (`ClaudeBot`), Perplexity (`PerplexityBot`), Googlebot, Bingbot, etc.
     - **Geographic Map**: Shows request volume by country, region, and city.
3. **Enable Cloudflare Web Analytics (Optional Free RUM)**:
   - In Cloudflare dashboard, go to **Web Analytics → Add a site**.
   - Cloudflare provides a single cookieless beacon script to measure Core Web Vitals and geographic breakdown with zero cookie banners required.
