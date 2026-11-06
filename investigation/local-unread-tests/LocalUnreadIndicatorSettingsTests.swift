import Foundation
import Postbox
import SwiftSignalKit
import TelegramCore
import TelegramUIPreferences

private func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fatalError("local unread test failed: \(message)")
    }
}

private func readState(_ signal: Signal<LocalUnreadIndicatorState, NoError>) -> LocalUnreadIndicatorState {
    var result: LocalUnreadIndicatorState?
    signal.start(next: { result = $0 })
    return result!
}

private func runChatListPolicyTests(peer: PeerId, otherPeer: PeerId) {
    let privatePeer = EnginePeer.user(peer)
    let groupPeer = EnginePeer.legacyGroup(peer)
    let broadcastPeer = EnginePeer.channel(.init(id: otherPeer, isForumOrMonoForum: false))
    let forumPeer = EnginePeer.channel(.init(id: peer, isForumOrMonoForum: true))

    let defaults = LocalUnreadIndicatorSettings.defaultSettings
    let emptyState = LocalUnreadIndicatorState(settings: defaults, unreadEnabledPeers: [])
    require(localChatUnreadIndicator(peer: privatePeer, threadId: nil, isUnread: true, state: emptyState) == .normal, "private chats always keep normal unread presentation")
    require(localChatUnreadIndicator(peer: .secretChat(peer), threadId: nil, isUnread: true, state: emptyState) == .normal, "secret chats keep normal unread presentation")
    require(localChatUnreadIndicator(peer: groupPeer, threadId: nil, isUnread: true, state: emptyState) == .hidden, "groups are hidden by default")
    require(localChatUnreadIndicator(peer: broadcastPeer, threadId: nil, isUnread: true, state: emptyState) == .hidden, "broadcast channels are hidden by default")

    let broadcastSettings = defaults.withUpdatedPeer(peerId: otherPeer, enabled: true)
    let broadcastState = LocalUnreadIndicatorState(settings: broadcastSettings, unreadEnabledPeers: [otherPeer])
    require(localChatUnreadIndicator(peer: broadcastPeer, threadId: nil, isUnread: true, state: broadcastState) == .dot(true), "enabled broadcast unread state produces a dot")
    require(localChatUnreadIndicator(peer: groupPeer, threadId: nil, isUnread: true, state: broadcastState) == .hidden, "an unenabled peer has no unread dot")

    let forumSettings = defaults
        .withUpdatedPeer(peerId: peer, enabled: true)
        .withUpdatedTopic(peerId: peer, threadId: 501, enabled: true)
        .withUpdatedTopic(peerId: otherPeer, threadId: 501, enabled: true)
    let forumState = LocalUnreadIndicatorState(settings: forumSettings, unreadEnabledPeers: [peer], topicUnreadStates: [peer: [501: true]])
    require(localChatUnreadIndicator(peer: forumPeer, threadId: nil, isUnread: true, state: forumState) == .dot(true), "forum parent dot follows selected unread topics")

    let staleForumState = LocalUnreadIndicatorState(settings: forumSettings, unreadEnabledPeers: [peer], topicUnreadStates: [peer: [501: false]])
    require(localChatUnreadIndicator(peer: forumPeer, threadId: nil, isUnread: true, state: staleForumState) == .dot(false), "forum parent ignores stale whole-peer unread state")
    require(localChatUnreadIndicator(peer: forumPeer, threadId: 501, isUnread: false, state: forumState) == .dot(true), "selected topic state overrides a stale row unread snapshot")
    require(localChatUnreadIndicator(peer: forumPeer, threadId: 501, isUnread: true, state: staleForumState) == .dot(false), "selected topic state remains authoritative when parent state is stale")
    require(localChatUnreadIndicator(peer: forumPeer, threadId: 502, isUnread: true, state: forumState) == .hidden, "unselected topic is hidden")

    let unavailableForumState = LocalUnreadIndicatorState(settings: forumSettings, unreadEnabledPeers: [])
    require(localChatUnreadIndicator(peer: forumPeer, threadId: 501, isUnread: true, state: unavailableForumState) == .dot(true), "unavailable selected topic falls back to its current row unread state")

    let staleUnreadTopic = EngineChatList.ForumTopicData(id: 501, title: "Selected", iconFileId: nil, iconColor: 0, maxOutgoingReadMessageId: EngineMessage.Id(), isUnread: true, threadPeer: nil)
    require(!localChatTopicUnreadPresentation(staleUnreadTopic, peer: forumPeer, state: staleForumState).isUnread, "topic preview clears stale unread emphasis when exact state is read")
    let staleReadTopic = EngineChatList.ForumTopicData(id: 501, title: "Selected", iconFileId: nil, iconColor: 0, maxOutgoingReadMessageId: EngineMessage.Id(), isUnread: false, threadPeer: nil)
    require(localChatTopicUnreadPresentation(staleReadTopic, peer: forumPeer, state: forumState).isUnread, "topic preview reflects exact unread state")

    let otherForumPeer = EnginePeer.channel(.init(id: otherPeer, isForumOrMonoForum: true))
    require(localChatUnreadIndicator(peer: otherForumPeer, threadId: nil, isUnread: true, state: forumState) == .dot(false), "same topic ID on another peer stays separate")
}

private func runSearchBadgePolicyTests(peer: PeerId) {
    let privatePeer = EnginePeer.user(peer)
    let groupPeer = EnginePeer.legacyGroup(peer)
    let defaults = LocalUnreadIndicatorState(settings: .defaultSettings, unreadEnabledPeers: [])

    require(localUnreadIndicatorBadge(peer: privatePeer, threadId: nil, unreadCount: nil, muted: false, state: defaults) == nil, "private peer without unread state has no search badge")
    require(localUnreadIndicatorBadge(peer: privatePeer, threadId: nil, unreadCount: 0, muted: false, state: defaults) == ContactsPeerItemBadge(count: 0, type: .active), "private marked-unread state keeps a zero-count search badge")
    require(localUnreadIndicatorBadge(peer: privatePeer, threadId: nil, unreadCount: 3, muted: true, state: defaults) == ContactsPeerItemBadge(count: 3, type: .inactive), "private unread count keeps normal muted search styling")
    require(localUnreadIndicatorBadge(peer: groupPeer, threadId: nil, unreadCount: 3, muted: false, state: defaults) == nil, "group search badge stays hidden by default")

    let enabled = LocalUnreadIndicatorState(settings: .defaultSettings.withUpdatedPeer(peerId: peer, enabled: true), unreadEnabledPeers: [peer])
    require(localUnreadIndicatorBadge(peer: groupPeer, threadId: nil, unreadCount: 3, muted: true, state: enabled) == ContactsPeerItemBadge(count: 0, type: .active), "enabled group search badge becomes an active dot")
}

@main
struct LocalUnreadIndicatorSettingsTests {
    static func main() {
        let peer = PeerId(0x1234567800000001)
        let otherPeer = PeerId(-0x000000007654321)

let defaults = LocalUnreadIndicatorSettings.defaultSettings
require(defaults.enabledPeers.isEmpty, "default peer opt-ins are empty")
require(defaults.enabledTopics.isEmpty, "default topic opt-ins are empty")

let peerEnabled = defaults.withUpdatedPeer(peerId: peer, enabled: true)
require(peerEnabled.isPeerEnabled(peerId: peer), "peer opt-in is enabled")
require(peerEnabled.enabledTopics.isEmpty, "peer opt-in preserves empty topics")

let topicEnabled = peerEnabled.withUpdatedTopic(peerId: peer, threadId: 0x7fff_ffff_0000_0001, enabled: true)
require(topicEnabled.isPeerEnabled(peerId: peer), "topic toggle preserves peer opt-in")
require(topicEnabled.isTopicEnabled(peerId: peer, threadId: 0x7fff_ffff_0000_0001), "topic opt-in is enabled")

let topicDisabled = topicEnabled.withUpdatedTopic(peerId: peer, threadId: 0x7fff_ffff_0000_0001, enabled: false)
require(topicDisabled.isPeerEnabled(peerId: peer), "last topic removal preserves peer opt-in")
require(topicDisabled.enabledTopics[peer] == nil, "last topic removal removes empty peer entry")

let roundTripInput = topicEnabled.withUpdatedPeer(peerId: otherPeer, enabled: true)
let encoded = try! JSONEncoder().encode(roundTripInput)
let roundTrip = try! JSONDecoder().decode(LocalUnreadIndicatorSettings.self, from: encoded)
require(roundTrip == roundTripInput, "64-bit peer and topic IDs survive Codable round trip")

let accountA = Postbox()
let accountB = Postbox()
updateLocalUnreadIndicatorSettingsInteractively(engine: TelegramEngine(postbox: accountA)) { _ in roundTrip }.start(next: { _ in })
var accountASettings: LocalUnreadIndicatorSettings?
localUnreadIndicatorSettings(engine: TelegramEngine(postbox: accountA)).start(next: { accountASettings = $0 })
var accountBSettings: LocalUnreadIndicatorSettings?
localUnreadIndicatorSettings(engine: TelegramEngine(postbox: accountB)).start(next: { accountBSettings = $0 })
require(accountASettings == roundTrip, "settings persist in account A")
require(accountBSettings == .defaultSettings, "settings do not leak across accounts")

let policyPostbox = Postbox()
let selectedUnreadThread: Int64 = 101
let selectedReadThread: Int64 = 102
let unselectedUnreadThread: Int64 = 103
let unavailableThread: Int64 = 104
policyPostbox.setThreadInfo(peerId: peer, threadId: selectedUnreadThread, unreadCount: 2, mutedUntil: 999999)
policyPostbox.setThreadInfo(peerId: peer, threadId: selectedReadThread, unreadCount: 0, markedUnread: true)
policyPostbox.setThreadInfo(peerId: peer, threadId: unselectedUnreadThread, unreadCount: 8)
policyPostbox.setUnreadState(peerId: otherPeer, count: 4)

let policySettings = LocalUnreadIndicatorSettings.defaultSettings
    .withUpdatedTopic(peerId: peer, threadId: selectedUnreadThread, enabled: true)
    .withUpdatedTopic(peerId: peer, threadId: selectedReadThread, enabled: true)
    .withUpdatedTopic(peerId: peer, threadId: unavailableThread, enabled: true)
    .withUpdatedPeer(peerId: otherPeer, enabled: true)
updateLocalUnreadIndicatorSettingsInteractively(engine: TelegramEngine(postbox: policyPostbox)) { _ in policySettings }.start(next: { _ in })
let state = readState(localUnreadIndicatorState(engine: TelegramEngine(postbox: policyPostbox)))
require(state.unreadSelectedPeers == [peer], "only selected unread topics produce a parent peer dot")
require(state.topicUnreadStates[peer] == [selectedUnreadThread: true, selectedReadThread: true], "selected topic booleans include marked-unread topics with zero unread messages")
require(state.unreadEnabledPeers == [otherPeer], "enabled peer unread state is reported")
require(state.topicUnreadStates[peer]?[unavailableThread] == nil, "unavailable topics are distinct from known read topics")
require(policyPostbox.observedKeys.count == 4, "only selected exact topics and enabled peers are observed")
require(policyPostbox.observedKeys.contains(.messageHistoryThreadInfo(peerId: peer, threadId: selectedUnreadThread)), "selected unread topic key is observed")
require(!policyPostbox.observedKeys.contains(.messageHistoryThreadInfo(peerId: peer, threadId: unselectedUnreadThread)), "unselected topic key is not observed")

policyPostbox.setThreadInfo(peerId: peer, threadId: selectedUnreadThread, unreadCount: 0)
let changedState = readState(localUnreadIndicatorState(engine: TelegramEngine(postbox: policyPostbox)))
require(changedState.unreadSelectedPeers == state.unreadSelectedPeers, "parent unread state can remain true while one selected topic changes")
require(changedState.topicUnreadStates[peer] == [selectedUnreadThread: false, selectedReadThread: true], "exact selected topic state changes are retained in Equatable state")

        let muteEngine = TelegramEngine(postbox: accountA)
        updateLocalMessageMuteSettings(engine: muteEngine, peerId: peer, muted: true).start(next: { _ in })
        localMessageMuteSettings(engine: muteEngine).start(next: { require($0.mutedPeerIds == [peer], "muted sender persists") })
        localMessageMuteSettings(engine: TelegramEngine(postbox: accountB)).start(next: { require($0.mutedPeerIds.isEmpty, "muted senders stay account-local") })
        updateLocalMessageMuteSettings(engine: muteEngine, peerId: peer, muted: false).start(next: { _ in })
        localMessageMuteSettings(engine: muteEngine).start(next: { require($0.mutedPeerIds.isEmpty, "unmuting removes only the selected sender") })

        let archivePostbox = Postbox()
        archivePostbox.archiveTotals = TestUnreadTotals(counts: [.contact: 2, .nonContact: 3, .bot: 1, .group: 99])
        archivePostbox.basicPeers[peer] = BasicPeerView(groupId: PeerGroupId(rawValue: 1), peer: TestPeer(id: peer, kind: .group))
        archivePostbox.basicPeers[otherPeer] = BasicPeerView(groupId: PeerGroupId(rawValue: 0), peer: TestPeer(id: otherPeer, kind: .group))
        let archiveSettings = defaults.withUpdatedPeer(peerId: peer, enabled: true).withUpdatedPeer(peerId: otherPeer, enabled: true)
        let archiveState = LocalUnreadIndicatorState(settings: archiveSettings, unreadEnabledPeers: [peer, otherPeer])
        localArchiveUnreadCount(engine: TelegramEngine(postbox: archivePostbox), state: archiveState).start(next: {
            require($0 == 7, "archive includes maintained private totals plus only selected unread archived groups")
        })
        archivePostbox.basicPeers[peer] = BasicPeerView(groupId: PeerGroupId(rawValue: 0), peer: TestPeer(id: peer, kind: .group))
        localArchiveUnreadCount(engine: TelegramEngine(postbox: archivePostbox), state: archiveState).start(next: {
            require($0 == 6, "moving an opted-in group out of archive removes its contribution")
        })

        runChatListPolicyTests(peer: peer, otherPeer: otherPeer)
        runSearchBadgePolicyTests(peer: peer)

        print("local unread settings and policy tests passed")
    }
}
