# Book-Source Search MVP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver the first usable iOS app slice: users can import/manage Legado book sources and search all enabled sources with partial results and per-source diagnostics.

**Architecture:** A SwiftUI app shell calls a local source store and a source-search coordinator. The coordinator fans requests out through an isolated networking and rule-runtime layer; each source failure is reported independently, and merged results retain their source origins. Reader detail/TOC/chapters and the full bookshelf workflow are a follow-on plan so this phase remains independently testable.

**Tech Stack:** Swift, SwiftUI, SwiftData, URLSession, JavaScriptCore, SwiftSoup, Kanna, XCTest. No server component.

**Spec:** `docs/superpowers/specs/2026-10-20-ios-reading-app-design.md`

## Global Constraints

- The app directly accesses user-configured third-party sites; it does not depend on a project-owned backend.
- User source import targets Legado JSON; no second general-purpose source format is added in this phase.
- Search uses bounded concurrency, per-source timeouts, cancellation, partial results, and preserved source provenance.
- Rules execute with time/resource limits and without access to local files, Keychain, or internal app data.
- Do not add EPUB/TXT/CBZ local-library support, annotations, notes, bookmarks, reading statistics, iCloud sync, or advertising.
- Reference repositories remain read-only; do not copy their source code, branding, or unverified source data.
- Bundle production default sources only after their distribution conditions are reviewed and each source's search flow is verified. Until then, test fixtures stay test-only; do not invent live defaults.
- The current Windows workspace has no `swift` or `xcodebuild`; build/test verification requires a macOS host with Xcode.

---

## File Map

- `BookReaderIOS.xcodeproj/project.pbxproj` — iOS app and XCTest target configuration.
- `App/BookReaderIOSApp.swift`, `App/RootView.swift` — app entry point and navigation shell.
- `Core/BookSource/BookSource.swift` — Codable and persisted source model.
- `Core/BookSource/BookSourceImport.swift` — Legado single/array JSON decoding and validation.
- `Core/BookSource/BookSourceStore.swift` — local persistence and seed initialization policy.
- `Core/Networking/SourceRequest.swift`, `SourceHTTPClient.swift` — request construction and URLSession execution.
- `Core/RuleEngine/RuleValue.swift`, `LegadoRuleParser.swift`, `JavaScriptRuleRuntime.swift` — typed extraction, supported rule operators, and constrained JS evaluation.
- `Core/Search/SourceSearchService.swift`, `SearchCoordinator.swift`, `SearchModels.swift` — one-source execution, bounded fan-out, aggregation and source outcomes.
- `Features/Sources/SourceListView.swift`, `SourceImportView.swift`, `SourceDebugView.swift` — source management UI.
- `Features/Search/SearchView.swift`, `SearchResultsView.swift` — query entry and streaming result UI.
- `Tests/Fixtures/BookSources/`, `Tests/Fixtures/Search/` — test-only source JSON and HTTP response fixtures.
- `Tests/BookSourceImportTests.swift`, `BookSourceStoreTests.swift`, `LegadoRuleParserTests.swift`, `SourceHTTPClientTests.swift`, `SearchCoordinatorTests.swift`, `SourceSearchFlowUITests.swift` — deterministic acceptance coverage.

## Task 1: Create a buildable iOS app shell

**Files:** Create the Xcode project, app entry/root view, app unit-test target and UI-test target.

**Interfaces:** `BookReaderIOSApp` launches `RootView`. `RootView` exposes two top-level destinations: `SearchView` and `SourceListView`; both initially render empty states.

- [ ] Create an iOS 17+ SwiftUI app target named `BookReaderIOS` and unit/UI test targets. Keep app code under `App/`, `Core/`, and `Features/`.
- [ ] Add `RootView` with navigation links to Search and Sources and accessible labels for UI tests.
- [ ] Run `xcodebuild -project BookReaderIOS.xcodeproj -scheme BookReaderIOS -destination 'platform=iOS Simulator,name=iPhone 16' test` on macOS; expected result is both test targets build and an empty-state smoke test passes.
- [ ] Commit the shell as `chore: create iOS app shell`.

## Task 2: Define source model, import, local persistence, and seed policy

**Files:** Create `Core/BookSource/BookSource.swift`, `BookSourceImport.swift`, `BookSourceStore.swift`, import/store tests and JSON fixtures.

**Interfaces:**

```swift
struct BookSource: Codable, Identifiable, Sendable {
    var id: String { bookSourceURL }
    let bookSourceName: String
    let bookSourceURL: String
    var enabled: Bool
    let searchURL: String?
    let ruleSearch: [String: String]
    let requestHeaders: [String: String]
    let cookie: String?
}

enum BookSourceImport {
    static func decode(_ data: Data) throws -> [BookSource]
}

@MainActor protocol BookSourceStore {
    func all() throws -> [BookSource]
    func importSources(_ sources: [BookSource]) throws -> Int
    func setEnabled(_ enabled: Bool, sourceID: String) throws
    func delete(sourceID: String) throws
}
```

- [ ] Add a failing test for decoding one source and a source array, preserving headers/cookie and rejecting malformed or unsupported records.
- [ ] Add a store test that imports sources idempotently by normalized source URL, toggles enabled state, deletes a source, and preserves user changes on a simulated seed-version update.
- [ ] Implement the smallest Codable model/store satisfying those tests. Keep arbitrary rule fields Codable so unsupported extensions round-trip without being executed.
- [ ] Test that a bundled-seed loader imports only validated app-bundled records once per seed version and never re-enables, overwrites, or resurrects a user-edited/deleted source.
- [ ] Keep production seed data absent until a source manifest is approved and verified; use only `example.invalid`/fixture hosts in tests.
- [ ] Run the source import/store XCTest suite; expected result is all tests pass with no network access.
- [ ] Commit as `feat: add local book source storage and import`.

## Task 3: Implement request construction and core Legado rule extraction

**Files:** Create `Core/Networking/SourceRequest.swift`, `SourceHTTPClient.swift`, `Core/RuleEngine/RuleValue.swift`, `LegadoRuleParser.swift`, `JavaScriptRuleRuntime.swift`, parser/network tests and fixtures.

**Interfaces:**

```swift
struct SourceRequest: Sendable {
    let url: URL
    let method: String
    let headers: [String: String]
    let body: Data?
}

protocol SourceHTTPClient {
    func data(for request: SourceRequest, timeout: Duration) async throws -> (Data, URLResponse)
}

enum LegadoRuleParser {
    static func extract(_ rule: String, from input: RuleValue) throws -> [RuleValue]
}
```

- [ ] Add parser tests first for search fixture shapes: CSS selector + attribute/text, XPath selection, JSONPath selection, regex extraction, and deterministic empty/malformed results.
- [ ] Add `URLProtocol`-backed HTTP tests proving method, headers and body are preserved, timeouts surface as per-request errors, and task cancellation cancels the request.
- [ ] Implement request interpolation for `{{key}}` values with URL-component-safe query escaping; never concatenate an unescaped search query into a URL.
- [ ] Implement extraction adapters using SwiftSoup for CSS and Kanna for XPath; use a bounded JSONPath subset and Foundation regex where the fixture corpus demonstrates Legado-compatible behavior.
- [ ] Implement JavaScript rule evaluation in JavaScriptCore behind a dedicated runtime with execution deadline and a deny-by-default bridge; add tests that timeout and that file/Keychain APIs are unavailable.
- [ ] Run all parser/network XCTest cases; expected result is deterministic pass with no live-site dependency.
- [ ] Commit as `feat: add bounded Legado request and rule runtime`.

## Task 4: Build source search fan-out and aggregation

**Files:** Create `Core/Search/SearchModels.swift`, `SourceSearchService.swift`, `SearchCoordinator.swift` and coordinator tests.

**Interfaces:**

```swift
struct SearchBook: Identifiable, Sendable {
    let id: String
    let title: String
    let author: String?
    let detailURL: String
    var sourceIDs: [String]
}

struct SourceSearchOutcome: Identifiable, Sendable {
    let id: String
    let sourceName: String
    let status: Status
    let books: [SearchBook]
    enum Status: Sendable { case found(Int), empty, failed(String), timedOut }
}

@MainActor final class SearchCoordinator: ObservableObject {
    @Published private(set) var books: [SearchBook] = []
    @Published private(set) var outcomes: [SourceSearchOutcome] = []
    func search(_ keyword: String, sources: [BookSource]) async
    func cancel()
}
```

- [ ] Add fake-service tests proving only enabled sources run and the configured maximum number run concurrently.
- [ ] Add tests proving early source results publish before slower tasks finish; a failure or timeout from one source does not erase other results; cancellation stops outstanding work.
- [ ] Add merge tests proving normalized title+author duplicates retain every origin and preserve each source-specific detail URL.
- [ ] Implement search rule execution as one isolated service call per source and an actor-backed result accumulator; sort by exact-title match, then normalized title/author, while retaining source order as a stable tie-breaker.
- [ ] Run coordinator tests with fake services only; expected result is no live-site dependency.
- [ ] Commit as `feat: search enabled book sources concurrently`.

## Task 5: Wire source management and search UI

**Files:** Create `Features/Sources/SourceListView.swift`, `SourceImportView.swift`, `SourceDebugView.swift`, `Features/Search/SearchView.swift`, `SearchResultsView.swift` and UI tests; update `App/RootView.swift`.

**Interfaces:** Source views consume `BookSourceStore`; `SearchView` consumes `SearchCoordinator` and the store. `SearchResultsView` renders each aggregated book once and a per-source status list without discarding partial results.

- [ ] Add UI tests for importing a test source JSON, toggling it on/off, and seeing the enabled state reflected in Search source count.
- [ ] Add UI tests for submitting a search against a stubbed source transport, showing partial results and a per-source failure message.
- [ ] Build the source list with import (paste/file/URL), enabled switch, delete confirmation, test action, and clear empty state. Do not add external source catalogs or live default records in this task.
- [ ] Build Search with query entry, enabled-source count, incremental results, source origins and empty/error states; keep UI strings localized in Simplified Chinese for the first release.
- [ ] Run unit tests and `SourceSearchFlowUITests` on an iOS simulator; expected result is import→search→partial result UI passes using fixtures.
- [ ] Commit as `feat: add source management and multi-source search UI`.

## Follow-on scope and release gates

- Book detail, table of contents, online chapter reader, source switching, bookshelf, reading-position restore and chapter cache require a separate plan before implementation.
- A real default-source manifest is a release gate, not a parser test fixture. Before adding source records, record each source's author/provenance, license or permission basis, intended audience, test date, and whether it actually supports in-app chapter reading. Metadata-only sources do not count as reading sources.
- A macOS Xcode environment is required to execute every `xcodebuild` verification command in this plan; the current Windows workspace cannot establish an iOS build result.
