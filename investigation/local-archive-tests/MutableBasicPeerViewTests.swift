import Foundation

private final class TestPeer: Peer {
    let value: Int

    init(value: Int) {
        self.value = value
    }

    func isEqual(_ other: Peer) -> Bool {
        return (other as? TestPeer)?.value == self.value
    }
}

private func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fatalError("basic peer view test failed: \(message)")
    }
}

@main
struct MutableBasicPeerViewTests {
    static func main() {
        let peerId = PeerId(1)
        let postbox = PostboxImpl(peer: TestPeer(value: 1), groupId: .root)
        let view = MutableBasicPeerView(postbox: postbox, peerId: peerId)

        require(!view.refreshDueToExternalTransaction(postbox: postbox), "unchanged state does not emit")

        postbox.chatListIndexTable.index.inclusion = .included(.group(1))
        require(view.refreshDueToExternalTransaction(postbox: postbox), "group changes emit")
        let movedView = view.immutableView() as! BasicPeerView
        require(movedView.groupId == .group(1), "group change is reflected")
        require(!view.refreshDueToExternalTransaction(postbox: postbox), "unchanged archive state does not emit")

        postbox.peerTable.peer = nil
        require(view.refreshDueToExternalTransaction(postbox: postbox), "deleted peer emits")
        let deletedView = view.immutableView() as! BasicPeerView
        require(deletedView.peer == nil, "deleted peer is cleared")

        print("basic peer view refresh tests passed")
    }
}
