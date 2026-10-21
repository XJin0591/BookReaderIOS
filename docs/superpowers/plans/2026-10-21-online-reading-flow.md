# Online Reading Flow Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the client-only Legado flow from a search result through book details and chapters to online chapter text in native SwiftUI.

**Architecture:** Keep HTTP and rule evaluation in a `LegadoBookService` implementation injected with the existing `SourceHTTPClient`. Preserve concrete detail URLs in search results, add backward-compatible Legado rule fields to `BookSource`, and keep navigation/loading state in small SwiftUI views. Do not persist chapter text or add server, caching, library, or reading-progress behavior.

**Tech Stack:** Swift 5, SwiftUI, Foundation URLSession, XCTest, URLProtocol fixtures, GitHub Actions macOS runner.

**Spec:** `docs/superpowers/specs/2026-10-21-reading-flow-design.md`

## Global Constraints

- All network requests are made directly by the iOS client to user-configured third-party Legado sources.
- Use existing `SourceHTTPClient`, `SourceRequest` and `LegadoRuleParser`; add no third-party dependency.
- Do not add server-side support, accounts/login, library/favorites, reading-position persistence, statistics, annotations, notes, bookmarks, iCloud sync, ads, EPUB/TXT/CBZ import, chapter cache, offline reading, preloading, or WebView content rendering.
- Keep old source JSON and locally saved source data decodable when new rules are absent.
- Verify compilation and tests using the repository's GitHub Actions macOS runner.

---

## File Map

- `Core/BookSource/BookSource.swift`: add `ruleBookInfo`, `ruleToc`, and `ruleContent` with compatible JSON coding.
- `Core/Search/SearchModels.swift`: make each search result's detail URL optional and represent missing detail destinations.
- `Core/Search/SourceSearchService.swift`: extract book list entries and resolve title, author, and detail URL.
- `Core/RuleEngine/LegadoRuleParser.swift`: expose minimal HTML element/field extraction needed by search, detail, TOC, and content rule selectors.
- `Core/Reading/ReadingModels.swift`: define `BookDetail`, `BookChapter`, and `ChapterContent`.
- `Core/Reading/LegadoBookService.swift`: define the async service contract.
- `Core/Reading/LegadoRemoteBookService.swift`: implement direct HTTP requests, rule extraction, URL resolution, and stage-specific errors.
- `Features/Search/SearchView.swift`: navigate searchable result rows to details and keep non-navigable results identifiable.
- `Features/Reading/BookDetailView.swift`: load/show book metadata and chapter list with progress, retry, and error states.
- `Features/Reading/ChapterReaderView.swift`: load/show current chapter text with progress, retry, and error states.
- `Tests/Unit/BookSourceImportTests.swift`: source rule-field compatibility.
- `Tests/Unit/SourceSearchServiceTests.swift`: list extraction and relative detail URL.
- `Tests/Unit/LegadoBookServiceTests.swift`: detail, TOC, content, errors, headers/cookie, and relative URL behavior.
- `Tests/UI/SourceSearchFlowUITests.swift`: retain stable app-entry smoke test; add UI coverage only for stable navigation elements.

## Task 1: Add backward-compatible Legado detail, TOC, and content rule fields

**Interfaces:**
- `BookSource.ruleBookInfo`, `BookSource.ruleToc`, and `BookSource.ruleContent` are `[String: String]`, defaulting to `[:]`.
- Existing initializer call sites remain source-compatible by adding defaulted parameters.

- [ ] Add a test to `BookSourceImportTests` that decodes three rules, re-encodes them, and decodes an older source object with no new fields:

~~~swift
func testDecodesAndEncodesDetailTocAndContentRules() throws {
    let data = Data(#"{"bookSourceName":"源","bookSourceUrl":"https://example.invalid","ruleBookInfo":{"name":".title"},"ruleToc":{"chapterList":".chapter"},"ruleContent":{"content":".content"}}"#.utf8)
    let source = try XCTUnwrap(BookSourceImport.decode(data).first)
    XCTAssertEqual(source.ruleBookInfo["name"], ".title")
    XCTAssertEqual(source.ruleToc["chapterList"], ".chapter")
    XCTAssertEqual(source.ruleContent["content"], ".content")

    let encoded = try JSONEncoder().encode(source)
    let decoded = try XCTUnwrap(BookSourceImport.decode(encoded).first)
    XCTAssertEqual(decoded, source)

    let old = Data(#"{"bookSourceName":"旧源","bookSourceUrl":"https://old.invalid"}"#.utf8)
    XCTAssertEqual(try BookSourceImport.decode(old).first?.ruleContent, [:])
}
~~~

- [ ] Run the focused test through the macOS workflow and confirm it fails because the fields are absent.
- [ ] Add the three defaulted properties and initializer parameters in `BookSource.swift`; include the keys in decode, encode, and the known-field set.
- [ ] Run the focused test and full unit suite in GitHub Actions; confirm both pass.
- [ ] Commit as `feat: add Legado detail toc and content rules`.

## Task 2: Preserve result-specific detail destinations and parse search rows

**Interfaces:**
- `SearchBook.detailURL` becomes `String?`.
- The initializer accepts `detailURL: String?`; its fallback map contains only non-nil URLs.
- `LegadoSourceSearchService.search(source:keyword:)` returns one `SearchBook` per matched book-list element; each result keeps `sourceIDs == [source.id]`.

- [ ] Add tests in `SourceSearchServiceTests.swift` with a URLProtocol fixture that returns:

~~~html
<div class="book"><a href="/book/1"><h2>书名一</h2></a><span class="author">作者一</span></div>
<div class="book"><a href="https://cdn.example.invalid/book/2"><h2>书名二</h2></a></div>
~~~

Use a source with `bookList: ".book"`, `name: "h2::text"`, `author: ".author::text"`, and `bookUrl: "a@href"`. Assert the two titles, optional author, resolved first URL, preserved absolute second URL, and that absent URLs stay nil.
- [ ] Run the focused test and confirm it fails against current single-string parsing.
- [ ] Add only the HTML extraction capability required to select element blocks, extract text/attributes from each block, and resolve HTTP(S) relative URLs against the response URL.
- [ ] Change `SearchBook.detailURL` to optional and update result merging so results without URLs still merge without inventing a destination.
- [ ] Run focused and full unit tests in GitHub Actions; confirm search aggregation and existing tests still pass.
- [ ] Commit as `feat: retain book detail URLs in search results`.

## Task 3: Add reading models and the remote Legado service

**Interfaces:**

~~~swift
public struct BookDetail: Identifiable, Equatable, Sendable {
    public let id: String
    public let sourceID: String
    public let title: String
    public let author: String?
    public let intro: String?
    public let coverURL: String?
    public let detailURL: String
    public let tocURL: String
}

public struct BookChapter: Identifiable, Equatable, Sendable {
    public let id: String
    public let sourceID: String
    public let title: String
    public let url: String
    public let index: Int
}

public struct ChapterContent: Equatable, Sendable {
    public let chapter: BookChapter
    public let text: String
}

public protocol LegadoBookService: Sendable {
    func detail(for book: SearchBook, source: BookSource) async throws -> BookDetail
    func chapters(for detail: BookDetail, source: BookSource) async throws -> [BookChapter]
    func content(for chapter: BookChapter, source: BookSource) async throws -> ChapterContent
}
~~~

- [ ] Add `LegadoBookServiceTests.swift` fixtures for one response per request stage. Assert detail fields and relative cover/toc URLs; chapter title, relative URL, and page-order index; chapter body text stripped of HTML; source header and Cookie propagation; status code on non-2xx; and stage-identifiable errors for unsupported URL and empty rule results.
- [ ] Run focused tests and confirm they fail because reading models and service do not exist.
- [ ] Add models to `ReadingModels.swift`; implement the protocol and `LegadoRemoteBookService` with injectable `SourceHTTPClient` and timeout.
- [ ] Resolve each returned URL relative to the correct response URL and accept only HTTP(S) URLs with a host.
- [ ] For each request, merge source headers and Cookie, reject non-2xx responses, decode HTML as UTF-8, and report an empty rule result as a localized stage error.
- [ ] For chapter text, remove markup and normalize line breaks without storing the result.
- [ ] Run focused and full unit tests in GitHub Actions; confirm all cases pass.
- [ ] Commit as `feat: fetch Legado book details chapters and content`.

## Task 4: Navigate search results to book details

**Interfaces:**
- Search rows with a `detailURL` resolve their source through `sourceIDs` and open `BookDetailView(book:source:)`.
- Rows without a detail URL remain visible but are not tappable and show “该书源未提供详情地址”.

- [ ] Add a test that only books with a valid HTTP(S) detail URL can be opened.
- [ ] Run the test and confirm the current result UI has no navigation destination.
- [ ] Replace the result `VStack` in `SearchView` with a `NavigationLink` for valid destinations; preserve title, author, source count, and source status sections.
- [ ] Keep unavailable results as a non-link row with the explanatory label.
- [ ] Run GitHub Actions unit and stable UI smoke tests; confirm search navigation compiles and existing entry smoke test passes.
- [ ] Commit as `feat: open details from search results`.

## Task 5: Build detail and chapter-list screen

**Interfaces:**
- `BookDetailView(book: SearchBook, source: BookSource)` loads `detail(for:source:)` then `chapters(for:source:)`.
- Success renders metadata and `NavigationLink` rows to `ChapterReaderView(chapter:source:)`.

- [ ] Add a view-model/service test for loading, success, and retry state transitions, injecting a fake `LegadoBookService`.
- [ ] Run the focused test and confirm the loading owner/state object does not exist.
- [ ] Add a small `@MainActor` observable model scoped to the reading feature; it stores only current detail, chapters, loading flag, and error.
- [ ] Implement `BookDetailView` with loading progress, optional cover, title/author/intro, chapter list, readable error, and retry button.
- [ ] Run unit tests and the GitHub Actions build; confirm the new SwiftUI screen compiles.
- [ ] Commit as `feat: show book details and chapter list`.

## Task 6: Build online chapter reader and verify full flow

**Interfaces:**
- `ChapterReaderView(chapter:source:)` calls `content(for:source:)` on appear and retry.
- Chapter body remains in memory for the lifetime of the view and provides no persistence or progress tracking.

- [ ] Add a view-model/service test for chapter loading, successful body display state, failure, and retry.
- [ ] Run the focused test and confirm the reader state does not exist.
- [ ] Implement `ChapterReaderView` with scrollable text, clear reading typography, loading progress, error and retry states.
- [ ] Add a stable UI smoke assertion for the detail/list/reader navigation entry only if accessibility identifiers are stable; keep fixture-network behavior in unit tests.
- [ ] Run `git diff --check`, then push the branch to trigger the complete GitHub Actions macOS test workflow.
- [ ] Inspect the final Actions result and test count; fix any regressions before reporting completion.
- [ ] Commit as `feat: read online Legado chapters`.

## Final Coverage Review

- [ ] Confirm the spec's data models, rules, request stages, UI flow, error categories, and test requirements each map to Tasks 1–6.
- [ ] Confirm no task adds any excluded feature or dependency.
- [ ] Confirm `SearchBook.detailURL` is optional at every constructor, merge, and UI call site.
- [ ] Confirm all service APIs in `ReadingModels.swift` and `LegadoBookService.swift` match Task 3 and Tasks 5–6 exactly.
