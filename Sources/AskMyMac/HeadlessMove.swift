import Darwin
import Foundation

/// `--selftest-move` plans a move, runs it as if approved, prints the undo record, then undoes it.
enum HeadlessMove {
    static func run(source: String, destination: String) -> Never {
        Task { @MainActor in
            let planned = ActionCenter.planMove(paths: [source], destinationFolder: destination)
            print(planned.previewText)
            fflush(stdout)
            guard planned.phase == .pending else { exit(1) }

            let done = ActionCenter.execute(planned)
            if let result = done.resultText, !result.isEmpty {
                print(result)
            }
            fflush(stdout)
            guard done.phase == .done, let undoID = done.undoID else { exit(1) }
            guard let record = UndoLog.jsonString(id: undoID) else {
                print("undo record missing")
                fflush(stdout)
                exit(1)
            }
            print(record)
            fflush(stdout)

            let undone = UndoLog.undo(id: undoID)
            print(undone.message)
            let origin = planned.transfers.first?.source ?? ""
            let landed = done.transfers.first?.destination ?? ""
            let back = !origin.isEmpty && FileManager.default.fileExists(atPath: origin)
            let leftBehind = !landed.isEmpty && FileManager.default.fileExists(atPath: landed)
            let restored = back && !leftBehind
            print(restored ? "The file is back." : "The file is not back.")
            fflush(stdout)
            exit(restored ? 0 : 1)
        }
        RunLoop.main.run()
        exit(1)
    }
}
