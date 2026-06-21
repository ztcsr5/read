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
}
