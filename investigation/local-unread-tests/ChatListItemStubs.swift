public enum ChatListUnreadIndicator: Equatable {
    case normal
    case hidden
    case dot(Bool)
}

public enum ContactsPeerItemBadgeType: Equatable {
    case active
    case inactive
}

public struct ContactsPeerItemBadge: Equatable {
    public let count: Int32
    public let type: ContactsPeerItemBadgeType

    public init(count: Int32, type: ContactsPeerItemBadgeType) {
        self.count = count
        self.type = type
    }
}
