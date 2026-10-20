import Foundation

final class MutableBasicPeerView: MutablePostboxView {
    private let peerId: PeerId
    fileprivate var peer: Peer?
    fileprivate var notificationSettings: PeerNotificationSettings?
    fileprivate var isContact: Bool
    fileprivate var groupId: PeerGroupId?
    
    init(postbox: PostboxImpl, peerId: PeerId) {
        self.peerId = peerId
        self.peer = postbox.peerTable.get(peerId)
        self.notificationSettings = postbox.peerNotificationSettingsTable.getEffective(peerId)
        self.isContact = postbox.contactsTable.isContact(peerId: self.peerId)
        self.groupId = postbox.chatListIndexTable.get(peerId: peerId).inclusion.groupId
    }
    
    func replay(postbox: PostboxImpl, transaction: PostboxTransaction) -> Bool {
        var updated = false
        if let peer = transaction.currentUpdatedPeers[self.peerId] {
            self.peer = peer
            updated = true
        }
        if transaction.currentUpdatedPeerNotificationSettings[self.peerId] != nil {
            self.notificationSettings = postbox.peerNotificationSettingsTable.getEffective(peerId)
            updated = true
        }
        if transaction.replaceContactPeerIds != nil {
            let isContact = postbox.contactsTable.isContact(peerId: self.peerId)
            if isContact != self.isContact {
                self.isContact = isContact
                updated = true
            }
        }
        if transaction.currentUpdatedChatListInclusions[self.peerId] != nil {
            let groupId = postbox.chatListIndexTable.get(peerId: peerId).inclusion.groupId
            if self.groupId != groupId {
                self.groupId = groupId
                updated = true
            }
        }
        
        return updated
    }

    func refreshDueToExternalTransaction(postbox: PostboxImpl) -> Bool {
        let peer = postbox.peerTable.get(self.peerId)
        let notificationSettings = postbox.peerNotificationSettingsTable.getEffective(self.peerId)
        let isContact = postbox.contactsTable.isContact(peerId: self.peerId)
        let groupId = postbox.chatListIndexTable.get(peerId: self.peerId).inclusion.groupId

        var updated = !arePeersEqual(self.peer, peer)
        switch (self.notificationSettings, notificationSettings) {
        case (nil, nil):
            break
        case let (lhs?, rhs?):
            if !lhs.isEqual(to: rhs) {
                updated = true
            }
        default:
            updated = true
        }
        if self.isContact != isContact || self.groupId != groupId {
            updated = true
        }

        self.peer = peer
        self.notificationSettings = notificationSettings
        self.isContact = isContact
        self.groupId = groupId

        return updated
    }
    
    func immutableView() -> PostboxView {
        return BasicPeerView(self)
    }
}

public final class BasicPeerView: PostboxView {
    public let peer: Peer?
    public let notificationSettings: PeerNotificationSettings?
    public let isContact: Bool
    public let groupId: PeerGroupId?
    
    init(_ view: MutableBasicPeerView) {
        self.peer = view.peer
        self.notificationSettings = view.notificationSettings
        self.isContact = view.isContact
        self.groupId = view.groupId
    }
}
