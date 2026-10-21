# 书籍详情、目录与在线章节阅读设计规格

## 目标

在现有多书源搜索基础上，增加一个不依赖自建服务器的原生阅读闭环：

搜索结果 → 书籍详情 → 章节目录 → 在线章节正文

客户端只请求用户启用的第三方 Legado 书源，不上传用户数据，也不引入 EPUB/TXT/CBZ 本地书库。

## 范围

本阶段包含：

- 从搜索结果进入书籍详情。
- 使用 Legado ruleBookInfo 解析作者、简介、封面和目录地址。
- 使用 Legado ruleToc 解析章节标题和章节地址。
- 使用 Legado ruleContent 解析章节正文。
- 原生 SwiftUI 详情页、目录页和正文阅读页。
- 请求超时、HTTP 错误、无效地址和规则无结果的可读错误提示。
- 单元测试覆盖规则解析、相对 URL、请求错误和三段请求链。

本阶段不包含：

- 服务器端、账号和登录。
- 书架、收藏、阅读位置恢复、阅读统计。
- 标注、笔记、书签、iCloud 同步和广告。
- EPUB/TXT/CBZ 导入。
- 章节缓存、离线阅读和预加载。
- WebView 作为正文展示方案。

## 现有代码约束

- 继续使用当前新仓库和 feature/book-source-search-mvp 分支。
- 两个参考项目只作为行为参考，不修改、不复制未确认许可的代码、品牌或来源列表。
- 使用现有 SourceHTTPClient、SourceRequest 和 LegadoRuleParser，不增加第三方依赖。
- 所有网络请求均由 iOS 客户端直接发出。
- GitHub Actions 的 macOS runner 是唯一的编译验证环境，本机不假定存在 Xcode。

## 数据模型

在 BookSource 中新增三个可选规则字典，字段名与 Legado JSON 保持一致：

- ruleBookInfo: [String: String]
- ruleToc: [String: String]
- ruleContent: [String: String]

三个字段缺失时使用空字典，现有已保存书源可以继续解码。它们作为已知字段编码，不再进入 additionalFields。

新增只读业务模型：

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
~~~

SearchBook.detailURL 必须保留具体书籍详情地址；如果书源没有提供详情地址，则该来源的搜索结果不能进入详情请求，并在来源状态中给出原因。

## 规则与请求链

### 1. 搜索结果

搜索列表规则继续使用 ruleSearch["bookList"]。对每个列表块：

- 标题使用 ruleSearch["name"]。
- 作者使用 ruleSearch["author"]，可为空。
- 详情地址使用 ruleSearch["bookUrl"]。
- 详情地址是相对路径时，以书源地址作为基准解析。
- 缺少 name 时回退到列表块文本；缺少 bookUrl 时回退为无详情地址，不伪造书源首页。

### 2. 书籍详情

请求 SearchBook.detailURL，应用 ruleBookInfo：

- name：标题，缺失时回退到搜索标题。
- author：作者。
- intro：简介。
- coverUrl：封面地址，可为空；相对地址按详情页 URL 解析。
- tocUrl：目录地址；缺失时使用详情页 URL。

详情阶段输出 BookDetail，并保留最终目录地址。

### 3. 章节目录

请求 BookDetail.tocURL，应用 ruleToc：

- chapterList：章节列表选择器。
- chapterName：章节标题。
- chapterUrl：章节地址。
- 相对章节地址按目录页 URL 解析。
- 缺少标题时使用章节块文本；缺少地址的章节丢弃，不创建不可点击行。

章节按页面顺序生成连续 index，不做去重以外的排序。

### 4. 章节正文

请求 BookChapter.url，应用 ruleContent：

- content：正文选择器。
- 结果先移除 HTML 标签，再将连续空白归一化为换行。
- 正文为空时返回可读错误，不展示空白阅读页。

现有规则引擎继续支持 CSS、XPath、JSONPath 和正则基础形式；本阶段不引入 JavaScript 作为正文主路径。规则无法解析时返回带阶段名称的诊断错误。

## 服务边界

新增 LegadoBookService 协议和默认实现 LegadoRemoteBookService：

~~~swift
public protocol LegadoBookService: Sendable {
    func detail(for book: SearchBook, source: BookSource) async throws -> BookDetail
    func chapters(for detail: BookDetail, source: BookSource) async throws -> [BookChapter]
    func content(for chapter: BookChapter, source: BookSource) async throws -> ChapterContent
}
~~~

服务只负责请求、URL 解析和规则提取，不持有 SwiftUI 状态。每个阶段使用现有超时机制和请求头/Cookie 规则。

## UI 数据流

- SearchView 将每个 SearchBook 包装为 NavigationLink，只有存在有效详情地址时可进入详情。
- BookDetailView 首次出现时加载详情和章节；加载期间显示进度，失败显示阶段错误和“重试”。
- 详情成功后显示标题、作者、简介、封面（可选）和章节列表。
- 点击章节进入 ChapterReaderView，在线加载正文；失败提供重试和返回目录。
- 阅读页只在内存中持有当前正文，不保存阅读位置。

## 错误处理

错误分为四类并在 UI 中显示中文文案：

- 地址错误：书源或规则生成的 URL 不是 HTTP(S)。
- 网络错误：超时、取消或底层连接失败。
- HTTP 错误：非 2xx 响应，包含状态码。
- 规则错误：规则缺失、无法解析或解析结果为空。

搜索来源的失败不影响其他来源；详情或章节失败只影响当前来源和当前书籍。

## 测试策略

单元测试使用 URLProtocol 注入响应，不访问真实网站：

1. BookSource 可以解码并编码三个新增规则字段，旧 JSON 仍可解码。
2. 搜索结果提取标题、作者和相对详情地址。
3. 详情、目录、正文分别从 fixture HTML 提取预期值。
4. 相对 URL、非 2xx、无效 URL、空规则结果返回确定错误。
5. 三段请求链使用同一来源请求头和 Cookie。
6. 现有搜索、书源导入、书源启停和规则运行时测试继续通过。

UI 测试只验证导航入口和静态页面存在，不依赖模拟器对 sheet 内部控件的脆弱可访问性树。

## 验收标准

- 用户可以从一个带完整 Legado 规则的搜索结果进入详情。
- 用户可以看到章节列表并打开任意章节正文。
- 所有网络请求均由客户端直接发起，无服务器配置。
- 错误不会导致应用崩溃，且能返回到上一级页面。
- GitHub Actions macOS runner 编译成功，单元测试和稳定的 UI smoke test 全部通过。
