import GanchoDesign
import GanchoKit
import SwiftUI

/// The panel has one native sheet presentation slot. Keeping snippet filling
/// and board appearance in one enum avoids the unreliable multiple-sheet state
/// that previously made presentations silently compete.
enum PanelPresentedSheet: Identifiable {
    case snippet(SnippetFillRequest)
    case boardAppearance(Pinboard)

    var id: String {
        switch self {
        case .snippet(let request): "snippet-\(request.id.uuidString)"
        case .boardAppearance(let board): "board-appearance-\(board.id.uuidString)"
        }
    }
}

/// The panel's modal layer: creating or renaming a board, confirming a board
/// deletion, and the snippet-fill and board-appearance sheets.
///
/// `PanelView` stays the single navigation owner — it still holds the state
/// these bind to and the focus and keyboard semantics around them. This
/// modifier owns only the presentation wiring, and reaches the app model
/// through closures so the modal layer cannot grow its own data dependencies.
struct PanelSheetPresentations: ViewModifier {
    let boardSheetTitle: LocalizedStringKey
    let boardSheetConfirm: LocalizedStringKey
    @Binding var boardSheetPresented: Bool
    @Binding var boardNameField: String
    @Binding var boardPendingDeletion: Pinboard?
    @Binding var presentedSheet: PanelPresentedSheet?
    let commitBoardSheet: () -> Void
    /// Also clears a board filter still pointing at the deleted board, which is
    /// why the caller supplies this rather than the modifier calling the model.
    let deleteBoard: (Pinboard) -> Void
    let pasteSnippet: (SnippetFillRequest, [String: String]) -> Void
    let updateBoardIdentity: @MainActor (Pinboard, String?, String?) async -> Bool

    func body(content: Content) -> some View {
        content
            .alert(boardSheetTitle, isPresented: $boardSheetPresented) {
                TextField("Board name", text: $boardNameField)
                Button("Cancel", role: .cancel) {}
                Button(boardSheetConfirm) { commitBoardSheet() }
            }
            .confirmationDialog(
                "Delete this board?",
                isPresented: Binding(
                    get: { boardPendingDeletion != nil },
                    set: { if !$0 { boardPendingDeletion = nil } }),
                presenting: boardPendingDeletion
            ) { board in
                Button("Delete board", role: .destructive) { deleteBoard(board) }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("Your clips stay in history — only the board is removed.")
            }
            .sheet(item: $presentedSheet) { sheet in
                switch sheet {
                case .snippet(let request):
                    SnippetFillSheet(request: request) { values in
                        pasteSnippet(request, values)
                        presentedSheet = nil
                    } onCancel: {
                        presentedSheet = nil
                    }
                case .boardAppearance(let board):
                    BoardIdentityEditor(board: board) { colorHex, emoji in
                        await updateBoardIdentity(board, colorHex, emoji)
                    }
                }
            }
    }
}
