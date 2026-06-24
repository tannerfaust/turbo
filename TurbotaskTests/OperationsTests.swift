import XCTest
@testable import Turbo

@MainActor
final class OperationsTests: XCTestCase {
    func testLegacyJobDecodesWithNoOperations() throws {
        let job = Job(title: "Field", summary: "", palette: .forest, projects: [])
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(job)) as? [String: Any])
        object.removeValue(forKey: "operations")
        let legacy = try JSONSerialization.data(withJSONObject: object)
        XCTAssertTrue(try JSONDecoder().decode(Job.self, from: legacy).operations.isEmpty)
    }

    func testOperationRoundTrip() throws {
        let operation = Operation(title: "Customer support", summary: "Keep response times low", tasks: [task()])
        let data = try JSONEncoder().encode(operation)
        XCTAssertEqual(try JSONDecoder().decode(Operation.self, from: data), operation)
    }

    func testAddOperationTrimsAndSelectsCreatedOperation() throws {
        let job = Job(title: "Field", summary: "", palette: .ocean, projects: [])
        let store = TurboTaskStore(jobs: [job], history: [], persistenceEnabled: false)

        let operationID = try XCTUnwrap(store.addOperation(title: "  Support  ", summary: "  Keep it running  ", jobID: job.id))

        XCTAssertEqual(store.jobs[0].operations.count, 1)
        XCTAssertEqual(store.jobs[0].operations[0].title, "Support")
        XCTAssertEqual(store.jobs[0].operations[0].summary, "Keep it running")
        XCTAssertEqual(store.selectedOperationID, operationID)
    }

    func testAddOperationRejectsMissingFieldAndBlankTitle() {
        let job = Job(title: "Field", summary: "", palette: .ocean, projects: [])
        let store = TurboTaskStore(jobs: [job], history: [], persistenceEnabled: false)

        XCTAssertNil(store.addOperation(title: "   ", summary: "Nope", jobID: job.id))
        XCTAssertNil(store.addOperation(title: "Support", summary: "", jobID: UUID()))
        XCTAssertTrue(store.jobs[0].operations.isEmpty)
    }

    func testArchiveAndRestoreOnlyCascadedTasks() {
        var alreadyArchived = task(title: "Old")
        alreadyArchived.isArchived = true
        let active = task(title: "Current")
        let operation = Operation(title: "Support", tasks: [alreadyArchived, active])
        let job = Job(title: "Field", summary: "", palette: .ocean, projects: [], operations: [operation])
        let store = TurboTaskStore(jobs: [job], history: [], persistenceEnabled: false)

        store.setOperationArchived(jobID: job.id, operationID: operation.id, archived: true)
        XCTAssertTrue(store.jobs[0].operations[0].tasks.allSatisfy(\.isArchived))
        XCTAssertFalse(store.nowTasks.contains { $0.operationID == operation.id })

        store.setOperationArchived(jobID: job.id, operationID: operation.id, archived: false)
        XCTAssertTrue(store.jobs[0].operations[0].tasks[0].isArchived)
        XCTAssertFalse(store.jobs[0].operations[0].tasks[1].isArchived)
    }

    func testTaskMovesExclusivelyBetweenProjectAndOperation() throws {
        let project = Project(title: "Launch", outcome: "Ship", tasks: [task()])
        let operation = Operation(title: "Support")
        let job = Job(title: "Field", summary: "", palette: .forest, projects: [project], operations: [operation])
        let store = TurboTaskStore(jobs: [job], history: [], persistenceEnabled: false)
        let context = try XCTUnwrap(store.taskContexts.first)

        XCTAssertTrue(store.updateTask(
            context: context,
            destinationJobID: job.id,
            destinationProjectID: nil,
            destinationOperationID: operation.id
        ) { _ in })

        let moved = try XCTUnwrap(store.taskContext(taskID: context.task.id))
        XCTAssertNil(moved.projectID)
        XCTAssertEqual(moved.operationID, operation.id)
    }

    private func task(title: String = "Task") -> Task {
        Task(
            title: title,
            summary: "",
            why: "",
            energy: .deepFocus,
            status: .queued,
            progress: 0,
            estimatedMinutes: 30,
            isScheduledNow: true,
            priority: 3,
            nextStep: ""
        )
    }
}
