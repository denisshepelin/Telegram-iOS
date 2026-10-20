import Foundation

private func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fatalError("thread info view test failed: \(message)")
    }
}

@main
struct MessageHistoryThreadInfoTests {
    static func main() {
        let peerId = PeerId(1)
        let threadId: Int64 = 10
        let postbox = PostboxImpl()
        postbox.messageHistoryThreadIndexTable.set(StoredMessageHistoryThreadInfo(unreadCount: 1), peerId: peerId, threadId: threadId)

        let view = MutableMessageHistoryThreadInfoView(postbox: postbox, peerId: peerId, threadId: threadId)
        require(!view.refreshDueToExternalTransaction(postbox: postbox), "unchanged state does not emit")

        postbox.messageHistoryThreadIndexTable.set(StoredMessageHistoryThreadInfo(unreadCount: 2), peerId: peerId, threadId: threadId)
        require(view.refreshDueToExternalTransaction(postbox: postbox), "changed state emits")
        let changedView = view.immutableView() as! MessageHistoryThreadInfoView
        require(changedView.info?.unreadCount == 2, "changed info is reflected")

        postbox.messageHistoryThreadIndexTable.set(nil, peerId: peerId, threadId: threadId)
        require(view.refreshDueToExternalTransaction(postbox: postbox), "removed state emits")
        let removedView = view.immutableView() as! MessageHistoryThreadInfoView
        require(removedView.info == nil, "removed info is reflected")
        require(!view.refreshDueToExternalTransaction(postbox: postbox), "unchanged missing state does not emit")

        print("thread info view refresh tests passed")
    }
}
