//! Link preview: Open Graph metadata fetching for URL previews.
//!
//! When a message contains URLs, this module fetches OG (Open Graph) metadata
//! (title, description, image) to display rich link preview cards in the UI.

use flutter_rust_bridge::frb;

use crate::api::error::BurrowError;

// ---------------------------------------------------------------------------
// FFI-friendly types
// ---------------------------------------------------------------------------

/// Open Graph metadata extracted from a URL.
#[frb(non_opaque)]
#[derive(Debug, Clone)]
pub struct OgMetadata {
    /// The original URL that was fetched.
    pub url: String,
    /// og:title — page title.
    pub title: Option<String>,
    /// og:description — page description (truncated to 300 chars).
    pub description: Option<String>,
    /// og:image — URL to a preview image/thumbnail.
    pub image_url: Option<String>,
    /// og:site_name — name of the website.
    pub site_name: Option<String>,
    /// Domain name extracted from the URL (e.g. "example.com").
    pub domain: String,
    /// og:type — content type (e.g. "article", "website").
    pub og_type: Option<String>,
}

// ---------------------------------------------------------------------------
// URL extraction
// ---------------------------------------------------------------------------

/// Extract URLs from a text string.
///
/// Returns a list of URLs found in the text. Uses a simple but effective
/// regex-free approach to find http:// and https:// URLs.
#[frb]
pub fn extract_urls(text: String) -> Vec<String> {
    let mut urls = Vec::new();
    for word in text.split_whitespace() {
        // Strip common trailing punctuation that's not part of URLs
        let cleaned = word.trim_end_matches(|c: char| {
            matches!(c, ',' | '.' | ')' | ']' | '>' | ';' | '!' | '?')
                && !word.ends_with("...")
        });
        if (cleaned.starts_with("https://") || cleaned.starts_with("http://"))
            && cleaned.len() > 10
        {
            urls.push(cleaned.to_string());
        }
    }
    urls
}

/// Extract the domain name from a URL.
fn extract_domain(url: &str) -> String {
    url.split("://")
        .nth(1)
        .unwrap_or(url)
        .split('/')
        .next()
        .unwrap_or(url)
        .split(':')
        .next()
        .unwrap_or(url)
        .to_string()
}

// ---------------------------------------------------------------------------
// OG metadata parsing (from HTML)
// ---------------------------------------------------------------------------

/// Parse Open Graph meta tags from raw HTML.
///
/// Looks for `<meta property="og:..." content="...">` and common fallbacks
/// like `<meta name="description">` and `<title>`.
fn parse_og_from_html(html: &str, url: &str) -> OgMetadata {
    let mut title: Option<String> = None;
    let mut description: Option<String> = None;
    let mut image_url: Option<String> = None;
    let mut site_name: Option<String> = None;
    let mut og_type: Option<String> = None;

    // Fallbacks from non-OG tags
    let mut html_title: Option<String> = None;
    let mut meta_description: Option<String> = None;

    // Parse using a simple state machine over <meta> and <title> tags.
    // We avoid pulling in the full `scraper` crate to keep binary size small.
    // Instead, use a lightweight approach with string searching.

    let html_lower = html.to_lowercase();

    // Extract <title>...</title>
    if let Some(start) = html_lower.find("<title") {
        if let Some(content_start) = html[start..].find('>') {
            let after = start + content_start + 1;
            if let Some(end) = html_lower[after..].find("</title") {
                let t = html[after..after + end].trim().to_string();
                if !t.is_empty() {
                    html_title = Some(decode_html_entities(&t));
                }
            }
        }
    }

    // Extract <meta> tags — iterate through all of them
    let mut search_from = 0;
    while let Some(meta_start) = html_lower[search_from..].find("<meta") {
        let abs_start = search_from + meta_start;
        let tag_end = match html_lower[abs_start..].find('>') {
            Some(e) => abs_start + e + 1,
            None => break,
        };
        let tag = &html[abs_start..tag_end];

        // Extract property and content attributes
        let property = extract_attr(tag, "property")
            .or_else(|| extract_attr(tag, "name"));
        let content = extract_attr(tag, "content");

        if let (Some(prop), Some(cont)) = (property, content) {
            let prop_lower = prop.to_lowercase();
            let cont = decode_html_entities(&cont);
            match prop_lower.as_str() {
                "og:title" => title = Some(cont),
                "og:description" => description = Some(truncate(&cont, 300)),
                "og:image" => image_url = Some(cont),
                "og:site_name" => site_name = Some(cont),
                "og:type" => og_type = Some(cont),
                "description" | "twitter:description" => {
                    if meta_description.is_none() {
                        meta_description = Some(truncate(&cont, 300));
                    }
                }
                "twitter:title" => {
                    if title.is_none() {
                        title = Some(cont);
                    }
                }
                "twitter:image" | "twitter:image:src" => {
                    if image_url.is_none() {
                        image_url = Some(cont);
                    }
                }
                _ => {}
            }
        }

        search_from = tag_end;
    }

    // Use fallbacks if OG tags are missing
    if title.is_none() {
        title = html_title;
    }
    if description.is_none() {
        description = meta_description;
    }

    // Resolve relative image URLs
    if let Some(ref img) = image_url {
        if img.starts_with('/') && !img.starts_with("//") {
            let base = format!(
                "{}://{}",
                if url.starts_with("https") { "https" } else { "http" },
                extract_domain(url)
            );
            image_url = Some(format!("{}{}", base, img));
        } else if img.starts_with("//") {
            image_url = Some(format!("https:{}", img));
        }
    }

    OgMetadata {
        url: url.to_string(),
        title,
        description,
        image_url,
        site_name,
        domain: extract_domain(url),
        og_type,
    }
}

/// Extract an HTML attribute value from a tag string.
fn extract_attr(tag: &str, attr_name: &str) -> Option<String> {
    // Search case-insensitively
    let tag_lower = tag.to_lowercase();
    let patterns = [
        format!("{}=\"", attr_name),
        format!("{}='", attr_name),
    ];

    for pattern in &patterns {
        if let Some(start) = tag_lower.find(pattern.as_str()) {
            let value_start = start + pattern.len();
            let quote_char = if pattern.ends_with('"') { '"' } else { '\'' };
            if let Some(end) = tag[value_start..].find(quote_char) {
                return Some(tag[value_start..value_start + end].to_string());
            }
        }
    }
    None
}

/// Decode common HTML entities.
fn decode_html_entities(s: &str) -> String {
    s.replace("&amp;", "&")
        .replace("&lt;", "<")
        .replace("&gt;", ">")
        .replace("&quot;", "\"")
        .replace("&#39;", "'")
        .replace("&apos;", "'")
        .replace("&#x27;", "'")
        .replace("&#x2F;", "/")
        .replace("&nbsp;", " ")
}

/// Truncate a string to max_len characters, appending "…" if truncated.
fn truncate(s: &str, max_len: usize) -> String {
    if s.chars().count() <= max_len {
        s.to_string()
    } else {
        let truncated: String = s.chars().take(max_len - 1).collect();
        format!("{}…", truncated)
    }
}

// ---------------------------------------------------------------------------
// Public FFI functions
// ---------------------------------------------------------------------------

/// Fetch Open Graph metadata for a URL.
///
/// Makes an HTTP GET request, follows redirects, and parses OG meta tags
/// from the HTML response. Returns metadata even if some fields are missing.
///
/// Timeout: 10 seconds. Only fetches the first 256KB of HTML to avoid
/// downloading large pages.
#[frb]
pub async fn fetch_og_metadata(url: String) -> Result<OgMetadata, BurrowError> {
    let client = reqwest::Client::builder()
        .timeout(std::time::Duration::from_secs(10))
        .connect_timeout(std::time::Duration::from_secs(5))
        .redirect(reqwest::redirect::Policy::limited(5))
        .user_agent("Burrow/1.0 (Link Preview)")
        .build()
        .map_err(|e| BurrowError::from(format!("HTTP client error: {}", e)))?;

    let resp = client
        .get(&url)
        .header("Accept", "text/html,application/xhtml+xml")
        .send()
        .await
        .map_err(|e| BurrowError::from(format!("Failed to fetch {}: {}", url, e)))?;

    // Check content type — only parse HTML
    let content_type = resp
        .headers()
        .get("content-type")
        .and_then(|v| v.to_str().ok())
        .unwrap_or("")
        .to_lowercase();

    if !content_type.contains("text/html") && !content_type.contains("application/xhtml") {
        // Not HTML — return minimal metadata with just the domain
        return Ok(OgMetadata {
            url: url.clone(),
            title: None,
            description: None,
            image_url: None,
            site_name: None,
            domain: extract_domain(&url),
            og_type: None,
        });
    }

    // Read response body, limited to 256KB to avoid huge pages
    let bytes = resp
        .bytes()
        .await
        .map_err(|e| BurrowError::from(format!("Failed to read response: {}", e)))?;

    let html = if bytes.len() > 256 * 1024 {
        String::from_utf8_lossy(&bytes[..256 * 1024]).to_string()
    } else {
        String::from_utf8_lossy(&bytes).to_string()
    };

    Ok(parse_og_from_html(&html, &url))
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_extract_urls() {
        let text = "Check out https://example.com/page and http://test.org/path?q=1 for more info.";
        let urls = extract_urls(text.to_string());
        assert_eq!(urls.len(), 2);
        assert_eq!(urls[0], "https://example.com/page");
        assert_eq!(urls[1], "http://test.org/path?q=1");
    }

    #[test]
    fn test_extract_urls_with_punctuation() {
        let text = "Visit https://example.com, or https://test.org.";
        let urls = extract_urls(text.to_string());
        assert_eq!(urls.len(), 2);
        assert_eq!(urls[0], "https://example.com");
        assert_eq!(urls[1], "https://test.org");
    }

    #[test]
    fn test_extract_urls_no_urls() {
        let text = "No links here, just plain text.";
        let urls = extract_urls(text.to_string());
        assert!(urls.is_empty());
    }

    #[test]
    fn test_extract_domain() {
        assert_eq!(extract_domain("https://www.example.com/path"), "www.example.com");
        assert_eq!(extract_domain("http://test.org:8080/foo"), "test.org");
        assert_eq!(extract_domain("https://sub.domain.co.uk/"), "sub.domain.co.uk");
    }

    #[test]
    fn test_parse_og_basic() {
        let html = r#"
            <html>
            <head>
                <title>Fallback Title</title>
                <meta property="og:title" content="OG Title">
                <meta property="og:description" content="A description of the page">
                <meta property="og:image" content="https://example.com/image.jpg">
                <meta property="og:site_name" content="Example Site">
                <meta property="og:type" content="article">
            </head>
            <body></body>
            </html>
        "#;
        let og = parse_og_from_html(html, "https://example.com/page");
        assert_eq!(og.title.as_deref(), Some("OG Title"));
        assert_eq!(og.description.as_deref(), Some("A description of the page"));
        assert_eq!(og.image_url.as_deref(), Some("https://example.com/image.jpg"));
        assert_eq!(og.site_name.as_deref(), Some("Example Site"));
        assert_eq!(og.og_type.as_deref(), Some("article"));
        assert_eq!(og.domain, "example.com");
    }

    #[test]
    fn test_parse_og_fallbacks() {
        let html = r#"
            <html>
            <head>
                <title>Page Title</title>
                <meta name="description" content="Meta description fallback">
            </head>
            <body></body>
            </html>
        "#;
        let og = parse_og_from_html(html, "https://example.com");
        assert_eq!(og.title.as_deref(), Some("Page Title"));
        assert_eq!(og.description.as_deref(), Some("Meta description fallback"));
        assert!(og.image_url.is_none());
    }

    #[test]
    fn test_parse_og_relative_image() {
        let html = r#"
            <meta property="og:image" content="/images/preview.jpg">
        "#;
        let og = parse_og_from_html(html, "https://example.com/page");
        assert_eq!(og.image_url.as_deref(), Some("https://example.com/images/preview.jpg"));
    }

    #[test]
    fn test_parse_og_protocol_relative_image() {
        let html = r#"
            <meta property="og:image" content="//cdn.example.com/img.png">
        "#;
        let og = parse_og_from_html(html, "https://example.com");
        assert_eq!(og.image_url.as_deref(), Some("https://cdn.example.com/img.png"));
    }

    #[test]
    fn test_parse_og_html_entities() {
        let html = r#"
            <meta property="og:title" content="Tom &amp; Jerry&#39;s &quot;Adventure&quot;">
        "#;
        let og = parse_og_from_html(html, "https://example.com");
        assert_eq!(og.title.as_deref(), Some("Tom & Jerry's \"Adventure\""));
    }

    #[test]
    fn test_parse_og_twitter_fallback() {
        let html = r#"
            <meta name="twitter:title" content="Twitter Title">
            <meta name="twitter:image" content="https://example.com/tw.jpg">
            <meta name="twitter:description" content="Twitter desc">
        "#;
        let og = parse_og_from_html(html, "https://example.com");
        assert_eq!(og.title.as_deref(), Some("Twitter Title"));
        assert_eq!(og.image_url.as_deref(), Some("https://example.com/tw.jpg"));
        assert_eq!(og.description.as_deref(), Some("Twitter desc"));
    }

    #[test]
    fn test_truncate() {
        assert_eq!(truncate("short", 10), "short");
        assert_eq!(truncate("a longer string here", 10), "a longer …");
    }

    #[test]
    fn test_decode_html_entities() {
        assert_eq!(
            decode_html_entities("&amp; &lt; &gt; &quot; &#39;"),
            "& < > \" '"
        );
    }
}
