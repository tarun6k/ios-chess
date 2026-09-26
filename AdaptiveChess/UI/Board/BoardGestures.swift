// boardView.ts pointer handling: tap-tap AND drag-and-drop on one gesture.
//
// pointerdown  → onSquareTap(sq); if that square holds a piece of the side to move it becomes
//                the drag origin.
// pointermove  → the first move lifts a ghost piece (and dims the origin); later moves follow
//                the finger.
// pointerup    → onDrop(from, to) only when a ghost was lifted and the finger ended on another
//                square; the ghost goes away either way (the caller snaps back by re-rendering).

import ChessCore
import SwiftUI

struct BoardDragState {
    /// `dragFrom`
    var from = -1
    /// `dragGhost !== null`
    var hasGhost = false
    /// the ghost's position in the grid's coordinate space
    var location: CGPoint?
    /// whether the current touch has already produced its pointerdown
    var pointerDown = false
}

private struct BoardGestures: ViewModifier {
    let state: BoardState
    /// the grid's bounding box (border included), like `getBoundingClientRect()`
    let size: CGSize
    @Binding var drag: BoardDragState
    let onSquareTap: (Int) -> Void
    let onDrop: (Int, Int) -> Void

    func body(content: Content) -> some View {
        content
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in
                        if !drag.pointerDown {
                            drag.pointerDown = true
                            pointerDown(at: value.location, in: size)
                        } else {
                            pointerMove(to: value.location)
                        }
                    }
                    .onEnded { value in
                        pointerUp(at: value.location, in: size)
                    }
            )
    }

    private func pointerDown(at point: CGPoint, in size: CGSize) {
        guard state.interactive else { return }
        let sq = BoardGeometry.square(at: point, in: size, flipped: state.flipped)
        guard sq >= 0 else { return }
        onSquareTap(sq)
        let piece = state.position.board[sq]
        if !piece.isEmpty && piece.color == state.position.turn {
            drag.from = sq
        }
    }

    private func pointerMove(to point: CGPoint) {
        guard drag.from >= 0 else { return }
        if !drag.hasGhost {
            guard !state.position.board[drag.from].isEmpty else { return }
            drag.hasGhost = true
        }
        drag.location = point
    }

    private func pointerUp(at point: CGPoint, in size: CGSize) {
        let wasDown = drag.pointerDown
        drag.pointerDown = false
        guard wasDown, drag.from >= 0 else {
            endDrag()
            return
        }
        let from = drag.from
        let wasDragging = drag.hasGhost
        let to = BoardGeometry.square(at: point, in: size, flipped: state.flipped)
        endDrag()
        if wasDragging && to >= 0 && to != from {
            onDrop(from, to)
        }
    }

    /// `endDrag`
    private func endDrag() {
        drag.from = -1
        drag.hasGhost = false
        drag.location = nil
    }
}

extension View {
    func boardGestures(
        state: BoardState,
        size: CGSize,
        drag: Binding<BoardDragState>,
        onSquareTap: @escaping (Int) -> Void,
        onDrop: @escaping (Int, Int) -> Void
    ) -> some View {
        modifier(BoardGestures(state: state, size: size, drag: drag, onSquareTap: onSquareTap, onDrop: onDrop))
    }
}
