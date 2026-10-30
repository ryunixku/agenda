import AgendaCore
import AgendaData
import SwiftUI

struct RootView: View {
    @Environment(AgendaStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.tab) {
            Tab("Now", systemImage: "checklist", value: .now) {
                NowView()
            }
            Tab("Lists", systemImage: "square.stack", value: .lists) {
                ListsView()
            }
            Tab("Calendar", systemImage: "calendar", value: .calendar) {
                CalendarScreen()
            }
            Tab("Archive", systemImage: "archivebox", value: .archive) {
                ArchiveView()
            }
        }
        .sheet(item: $router.openTask) { ref in
            TaskDetailView(taskID: ref.id)
                .environment(store)
                .environment(router)
        }
        .sheet(item: $router.rescheduling) { ref in
            RescheduleSheet(taskID: ref.id, agenda: store.agenda)
                .environment(store)
                .environment(router)
        }
        .alert("Can't do that", isPresented: Binding(get: { router.error != nil }, set: { if !$0 { router.error = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(router.error ?? "")
        }
        .overlay(alignment: .top) {
            if let banner = router.banner {
                BannerView(banner: banner)
                    .id(banner.id)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: router.banner?.id)
    }
}

/// A short message after an action, sometimes with a follow-up such as "Mark all done".
struct BannerView: View {
    let banner: Router.Banner
    @Environment(Router.self) private var router

    var body: some View {
        HStack(spacing: 12) {
            Text(banner.message)
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let title = banner.actionTitle, let action = banner.action {
                Button(title) {
                    action()
                    router.banner = nil
                }
                .font(.subheadline.bold())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: .rect(cornerRadius: 16))
        .padding(.horizontal)
        .task {
            try? await Task.sleep(for: .seconds(banner.actionTitle == nil ? 2.5 : 6))
            if router.banner?.id == banner.id { router.banner = nil }
        }
    }
}
