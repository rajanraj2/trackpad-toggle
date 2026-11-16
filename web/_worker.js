export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    // 1. Dynamic sitemap based on requested domain / host
    if (url.pathname === '/sitemap.xml') {
      const xml = `<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
  <url>
    <loc>${url.origin}/</loc>
    <lastmod>2026-11-16</lastmod>
    <changefreq>weekly</changefreq>
    <priority>1.0</priority>
  </url>
  <url>
    <loc>${url.origin}/llms.txt</loc>
    <lastmod>2026-11-16</lastmod>
    <changefreq>monthly</changefreq>
    <priority>0.8</priority>
  </url>
  <url>
    <loc>${url.origin}/llms-full.txt</loc>
    <lastmod>2026-11-16</lastmod>
    <changefreq>monthly</changefreq>
    <priority>0.7</priority>
  </url>
</urlset>`;
      return new Response(xml, {
        headers: {
          'Content-Type': 'application/xml; charset=utf-8',
          'Cache-Control': 'public, max-age=86400, stale-while-revalidate=604800',
        },
      });
    }

    // 2. Dynamic robots.txt based on requested domain / host
    if (url.pathname === '/robots.txt') {
      const robots = `# https://www.robotstxt.org/robotstxt.html
User-agent: *
Allow: /

# Specifically allow major AI search and retrieval agents
User-agent: GPTBot
Allow: /

User-agent: ChatGPT-User
Allow: /

User-agent: PerplexityBot
Allow: /

User-agent: ClaudeBot
Allow: /

User-agent: anthropic-ai
Allow: /

User-agent: Google-Extended
Allow: /

User-agent: Applebot
Allow: /

User-agent: Applebot-Extended
Allow: /

User-agent: Bingbot
Allow: /

User-agent: DuckDuckBot
Allow: /

# Dynamic Canonical Sitemap based on active domain
Sitemap: ${url.origin}/sitemap.xml
`;
      return new Response(robots, {
        headers: {
          'Content-Type': 'text/plain; charset=utf-8',
          'Cache-Control': 'public, max-age=86400, stale-while-revalidate=604800',
        },
      });
    }

    // 3. Fall through to static asset delivery
    return env.ASSETS.fetch(request);
  },
};
