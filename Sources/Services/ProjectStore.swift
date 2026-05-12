import Foundation

class ProjectStore: ObservableObject {
    private let key = "com.provenance.projects"
    @Published private(set) var projects: [Project] = []

    init() { load() }

    func add(_ project: Project) {
        projects.append(project)
        save()
    }

    func remove(id: UUID) {
        projects.removeAll { $0.id == id }
        save()
    }

    func update(_ project: Project) {
        if let idx = projects.firstIndex(where: { $0.id == project.id }) {
            projects[idx] = project
            save()
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key) else { return }
        projects = (try? JSONDecoder().decode([Project].self, from: data)) ?? []
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(projects) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
