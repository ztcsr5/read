import XCTest
@testable import SourceReadSwift

final class RSSFeedParserTests: XCTestCase {
    func testParsesRSSItems() {
        let xml = """
        <rss><channel>
          <item>
            <title><![CDATA[First &amp; One]]></title>
            <link>https://example.com/1</link>
            <pubDate>Sun, 21 Jun 2026 10:00:00 GMT</pubDate>
            <description><![CDATA[<p>Hello</p> World]]></description>
          </item>
          <item>
            <title>Second</title>
            <guid>https://example.com/2</guid>
          </item>
        </channel></rss>
        """

        let articles = RSSFeedParser().parseArticles(from: xml)

        XCTAssertEqual(articles.count, 2)
        XCTAssertEqual(articles[0].title, "First & One")
        XCTAssertEqual(articles[0].link, "https://example.com/1")
        XCTAssertEqual(articles[0].description, "Hello World")
        XCTAssertEqual(articles[1].title, "Second")
        XCTAssertEqual(articles[1].link, "https://example.com/2")
    }

    func testParsesAtomEntriesWithHrefLinks() {
        let xml = """
        <feed>
          <entry>
            <title>Atom Title</title>
            <link href="https://example.com/atom"/>
            <updated>2026-06-21T10:00:00Z</updated>
            <summary>Atom summary</summary>
          </entry>
        </feed>
        """

        let article = RSSFeedParser().parseArticles(from: xml).first

        XCTAssertEqual(article?.title, "Atom Title")
        XCTAssertEqual(article?.link, "https://example.com/atom")
        XCTAssertEqual(article?.pubDate, "2026-06-21T10:00:00Z")
        XCTAssertEqual(article?.description, "Atom summary")
    }

    func testPrefersAtomAlternateHTMLLinkOverSelfAndNonHTMLLinks() {
        let xml = """
        <feed xmlns="http://www.w3.org/2005/Atom">
          <entry>
            <title>Preferred</title>
            <link rel="self" href="https://example.com/api/entry" type="application/atom+xml" />
            <link rel="alternate" href="/stories/preferred" type="text/html" />
            <link rel="related" href="https://example.com/related" type="text/plain" />
          </entry>
        </feed>
        """

        let article = RSSFeedParser().parseArticles(from: xml, sourceURL: "https://example.com/feed").first

        XCTAssertEqual(article?.link, "https://example.com/stories/preferred")
    }

    func testResolvesRelativeRSSLinkAgainstFeedURL() {
        let xml = "<rss><channel><item><title>Relative</title><link>/article/1</link></item></channel></rss>"
        let article = RSSFeedParser().parseArticles(from: xml, sourceURL: "https://example.com/rss/feed.xml").first
        XCTAssertEqual(article?.link, "https://example.com/article/1")
    }

    func testExtractsArticleBodyParagraphs() {
        let html = "<html><body><nav>Menu</nav><article><h1>Title</h1><p>First</p><p>Second <b>part</b></p></article></body></html>"
        XCTAssertEqual(RSSArticleContentParser().parseParagraphs(from: html), ["Title", "First", "Second part"])
    }

    func testTracksSourceAndExtractsArticleImage() {
        let xml = """
        <rss><channel><item><title>Image</title><link>/article</link>
        <media:content url="/images/cover.jpg" /></item></channel></rss>
        """
        let article = RSSFeedParser().parseArticles(from: xml, sourceURL: "https://example.com/feed").first
        XCTAssertEqual(article?.sourceURL, "https://example.com/feed")
        XCTAssertEqual(article?.imageURL, "https://example.com/images/cover.jpg")
        XCTAssertEqual(article?.id.hasPrefix("https://example.com/feed|"), true)
    }

    func testExtractsEmbeddedContentHTMLAndDublinCoreDate() {
        let xml = """
        <rss xmlns:content="http://purl.org/rss/1.0/modules/content/" xmlns:dc="http://purl.org/dc/elements/1.1/"><channel><item>
          <title>Embedded</title><link>/embedded</link>
          <dc:date>2026-09-03T10:00:00Z</dc:date>
          <description><![CDATA[Short summary]]></description>
          <content:encoded><![CDATA[<article><h1>Embedded title</h1><p>Full body</p></article>]]></content:encoded>
        </item></channel></rss>
        """
        let article = RSSFeedParser().parseArticles(from: xml, sourceURL: "https://example.com/feed").first
        XCTAssertEqual(article?.pubDate, "2026-09-03T10:00:00Z")
        XCTAssertEqual(article?.description, "Short summary")
        XCTAssertEqual(article?.contentHTML, "<article><h1>Embedded title</h1><p>Full body</p></article>")
        XCTAssertEqual(RSSArticleContentParser().parseParagraphs(from: article?.contentHTML ?? ""), ["Embedded title", "Full body"])
    }

    func testDecodesLegacyArticlePreviewWithoutEmbeddedHTML() throws {
        let data = Data(#"{"title":"Legacy","link":null,"pubDate":null,"description":"Body","sourceURL":null,"imageURL":null}"#.utf8)
        let article = try JSONDecoder().decode(RSSArticlePreview.self, from: data)
        XCTAssertEqual(article.title, "Legacy")
        XCTAssertNil(article.contentHTML)
    }

    func testDeduplicatesRepeatedFeedItemsWithoutDroppingDistinctArticles() {
        let xml = """
        <rss><channel>
          <item><title>Same</title><link>https://example.com/same</link></item>
          <item><title>Same</title><link>https://example.com/same</link></item>
          <item><title>Other</title><link>https://example.com/other</link></item>
        </channel></rss>
        """

        let articles = RSSFeedParser().parseArticles(from: xml)

        XCTAssertEqual(articles.map(\.title), ["Same", "Other"])
    }
}
