import SwiftUI

struct RootView: View {
    var body: some View {
        NavigationStack {
            List {
                NavigationLink {
                    SearchView()
                } label: {
                    Label("搜索书籍", systemImage: "magnifyingglass")
                }

                NavigationLink {
                    SourceListView()
                } label: {
                    Label("书源管理", systemImage: "list.bullet.rectangle")
                }
            }
            .navigationTitle("阅读")
        }
    }
}
