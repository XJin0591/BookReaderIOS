import SwiftUI

struct RootView: View {
    @StateObject private var model = AppModel()

    var body: some View {
        NavigationStack {
            List {
                NavigationLink {
                    SearchView(model: model)
                } label: {
                    Label("搜索书籍", systemImage: "magnifyingglass")
                }

                NavigationLink {
                    SourceListView(model: model)
                } label: {
                    Label("书源管理", systemImage: "list.bullet.rectangle")
                }
            }
            .navigationTitle("阅读")
        }
    }
}
