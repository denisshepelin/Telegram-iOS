import AccountContext
import AsyncDisplayKit
import Display
import Foundation
import InstantPageUI
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import TelegramUIPreferences
import TextFormat
import UIKit

/// Presents one message snapshot using Instant View layout without webpage refresh or URL sharing.
final class MessageReaderController: ViewController, UIScrollViewDelegate {
    private let context: AccountContext
    private let message: EngineRawMessage
    private let instantPage: InstantPage
    private let webpage: TelegramMediaWebpage
    private let openMessageUrl: (InstantPageUrlItem) -> Void
    private var presentationData: PresentationData
    private var presentationDisposable: Disposable?
    private var readerSettings = InstantPagePresentationSettings.defaultSettings
    private let scrollView = UIScrollView()
    private var pageView: InstantPageV2View?
    private var expandedDetails: [Int: Bool] = [:]
    private var validLayout: ContainerViewLayout?

    init(context: AccountContext, message: EngineRawMessage, openUrl: @escaping (InstantPageUrlItem) -> Void) {
        self.context = context
        self.message = message
        self.instantPage = messageReaderInstantPage(message: message)
        self.webpage = messageReaderWebpage(instantPage: self.instantPage)
        self.openMessageUrl = openUrl
        self.presentationData = context.sharedContext.currentPresentationData.with { $0 }
        super.init(navigationBarPresentationData: NavigationBarPresentationData(presentationTheme: self.presentationData.theme, presentationStrings: self.presentationData.strings))
        self.title = self.presentationData.strings.Conversation_MessageReaderTitle
        self.statusBar.statusBarStyle = self.presentationData.theme.rootController.statusBarStyle.style
        self.presentationDisposable = (combineLatest(
            context.sharedContext.presentationData,
            context.sharedContext.accountManager.sharedData(keys: [ApplicationSpecificSharedDataKeys.instantPagePresentationSettings])
        ) |> deliverOnMainQueue).start(next: { [weak self] presentationData, sharedData in
            guard let self else { return }
            self.presentationData = presentationData
            self.readerSettings = sharedData.entries[ApplicationSpecificSharedDataKeys.instantPagePresentationSettings]?.get(InstantPagePresentationSettings.self) ?? .defaultSettings
            self.title = presentationData.strings.Conversation_MessageReaderTitle
            self.statusBar.statusBarStyle = presentationData.theme.rootController.statusBarStyle.style
            self.navigationBar?.updatePresentationData(NavigationBarPresentationData(presentationTheme: presentationData.theme, presentationStrings: presentationData.strings), transition: .immediate)
            self.updateReaderLayout()
        })
    }

    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        self.presentationDisposable?.dispose()
    }

    override func loadDisplayNode() {
        self.displayNode = ASDisplayNode()
        self.scrollView.alwaysBounceVertical = true
        self.scrollView.contentInsetAdjustmentBehavior = .never
        self.scrollView.delegate = self
        self.displayNode.view.addSubview(self.scrollView)
        let messageReference = MessageReference(self.message)
        let peerType: MediaAutoDownloadPeerType
        if let channel = self.message.peers[self.message.id.peerId] as? TelegramChannel {
            if case .broadcast = channel.info {
                peerType = .channel
            } else {
                peerType = .group
            }
        } else if self.message.peers[self.message.id.peerId] is TelegramGroup {
            peerType = .group
        } else {
            peerType = .otherPrivate
        }
        let renderContext = InstantPageV2RenderContext(
            context: self.context,
            webpage: self.webpage,
            sourceLocation: InstantPageSourceLocation(userLocation: .peer(self.message.id.peerId), peerType: peerType),
            imageReference: { .message(message: messageReference, media: $0) },
            fileReference: { .message(message: messageReference, media: $0) },
            present: { [weak self] controller, arguments in
                self?.present(controller, in: .window(.root), with: arguments)
            },
            push: { [weak self] controller in
                (self?.navigationController as? NavigationController)?.pushViewController(controller)
            },
            openUrl: { [weak self] url in self?.openReaderUrl(url) },
            baseNavigationController: { [weak self] in self?.navigationController as? NavigationController },
            message: messageReference
        )
        let pageView = InstantPageV2View(renderContext: renderContext)
        self.pageView = pageView
        self.scrollView.addSubview(pageView)
        pageView.detailsTapped = { [weak self] index in
            guard let self else { return }
            let current = self.expandedDetails[index] ?? self.defaultDetailsExpanded(index: index, items: self.pageView?.currentLayout?.items ?? [])
            self.expandedDetails[index] = !current
            self.updateReaderLayout()
        }
        let tap = UITapGestureRecognizer(target: self, action: #selector(self.readerTapped(_:)))
        tap.cancelsTouchesInView = false
        pageView.addGestureRecognizer(tap)
        self.displayNodeDidLoad()
    }

    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        self.validLayout = layout
        self.updateReaderLayout()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        self.updateReaderVisibility()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        self.pageView?.visibilityRect = nil
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        self.updateReaderVisibility()
    }

    private func updateReaderLayout() {
        guard let layout = self.validLayout, let pageView = self.pageView else { return }
        let navigationHeight = self.navigationLayout(layout: layout).navigationFrame.maxY
        let themeType: InstantPageThemeType = self.presentationData.theme.overallDarkAppearance && self.readerSettings.autoNightMode ? .dark : self.readerSettings.themeType
        let theme = instantPageThemeForType(themeType, settings: self.readerSettings)
        self.displayNode.backgroundColor = theme.pageBackgroundColor
        self.scrollView.indicatorStyle = themeType == .dark ? .white : .black
        self.scrollView.frame = CGRect(x: 0, y: navigationHeight, width: layout.size.width, height: max(0, layout.size.height - navigationHeight))
        self.scrollView.contentInset.bottom = layout.intrinsicInsets.bottom + 20
        let availableWidth = layout.size.width - layout.safeInsets.left - layout.safeInsets.right
        let width = min(760, availableWidth)
        let pageLayout = layoutInstantPageV2(
            webpage: self.webpage, instantPage: self.instantPage, userLocation: .peer(self.message.id.peerId),
            boundingWidth: width, horizontalInset: 20, theme: theme, strings: self.presentationData.strings,
            dateTimeFormat: self.presentationData.dateTimeFormat, cachedMessageSyntaxHighlight: nil,
            expandedDetails: self.expandedDetails, fitToWidth: true
        )
        pageView.update(layout: pageLayout, theme: theme, animation: .None)
        pageView.frame = CGRect(origin: CGPoint(x: layout.safeInsets.left + (availableWidth - width) / 2, y: 16), size: pageLayout.contentSize)
        self.scrollView.contentSize = CGSize(width: layout.size.width, height: pageLayout.contentSize.height + 16)
        self.updateReaderVisibility()
    }

    private func updateReaderVisibility() {
        guard let pageView else { return }
        pageView.visibilityRect = self.scrollView.convert(self.scrollView.bounds, to: pageView)
    }

    private func defaultDetailsExpanded(index: Int, items: [InstantPageV2LaidOutItem]) -> Bool {
        for item in items {
            if case let .details(details) = item {
                if details.index == index { return details.defaultExpanded }
                if let inner = details.innerLayout, self.defaultDetailsExpanded(index: index, items: inner.items) {
                    return true
                }
            }
        }
        return false
    }

    private func openReaderUrl(_ url: InstantPageUrlItem) {
        if url.url.hasPrefix("#"), let pageView, let frame = pageView.anchorFrame(name: String(url.url.dropFirst()).removingPercentEncoding ?? String(url.url.dropFirst())) {
            self.scrollView.scrollRectToVisible(frame.offsetBy(dx: pageView.frame.minX, dy: pageView.frame.minY), animated: true)
        } else {
            self.openMessageUrl(url)
        }
    }

    @objc private func readerTapped(_ recognizer: UITapGestureRecognizer) {
        guard let pageView else { return }
        let point = recognizer.location(in: pageView)
        if let hit = pageView.textItemAt(point: point) {
            let local = CGPoint(x: point.x - hit.parentOffset.x, y: point.y - hit.parentOffset.y)
            if let (_, attributes) = hit.item.attributesAtPoint(local, orNearest: false) {
                if !pageView.displayContentsUnderSpoilers, attributes[NSAttributedString.Key(rawValue: TelegramTextAttributes.Spoiler)] != nil {
                    pageView.setDisplayContentsUnderSpoilers(true, atLocation: point, animated: true)
                    return
                }
                if let mention = attributes[NSAttributedString.Key(rawValue: TelegramTextAttributes.PeerMention)] as? TelegramPeerMention {
                    self.openReaderUrl(InstantPageUrlItem(url: "tg://user?id=\(mention.peerId.id._internalGetInt64Value())", webpageId: nil))
                    return
                }
            }
        }
        if let hit = pageView.urlItemAt(point: point) {
            self.openReaderUrl(hit.urlItem)
        }
    }
}
