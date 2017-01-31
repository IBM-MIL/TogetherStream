//
//  StreamViewController.swift
//  Stormtrooper
//
//  Created by Nathan Hekman on 11/23/16.
//  Copyright © 2016 IBM. All rights reserved.
//

import UIKit

class StreamViewController: UIViewController {
    @IBOutlet weak var playerView: YTPlayerView!
    @IBOutlet weak var playPauseButton: UIButton!
    @IBOutlet weak var mediaControllerView: UIView!
	@IBOutlet weak var chatInputTextField: UITextField!
	@IBOutlet weak var chatTableView: UITableView!
	@IBOutlet weak var userCountLabel: UILabel!
    @IBOutlet weak var headerView: UIView!
    @IBOutlet weak var queueView: UIView!
    @IBOutlet weak var headerViewHeightConstraint: NSLayoutConstraint!
    @IBOutlet weak var headerArrowImageView: UIImageView!
    @IBOutlet weak var headerViewButton: UIButton!
    @IBOutlet weak var visualEffectView: UIVisualEffectView!
    @IBOutlet weak var profileImageView: UIImageView!
    @IBOutlet weak var dismissView: UIView!
    @IBOutlet weak var videoTitleLabel: UILabel!
    @IBOutlet weak var videoSubtitleLabel: UILabel!
    @IBOutlet weak var queueTableView: UITableView!
    
    //constraints
    private var originalHeaderViewHeightConstraint: CGFloat = 0
    fileprivate var estimatedChatCellHeight: CGFloat = 56
    
    //constants
    private let closeButtonFrame = CGRect(x: 0, y: 0, width: 17, height: 17)
    private let profileButtonFrame = CGRect(x: 0, y: 0, width: 19, height: 24)
    private let headerViewAnimationDuration: TimeInterval = 0.3
    fileprivate let chatTableTag = 0
    fileprivate let queueTableTag = 1
    fileprivate let playerVars = [ //TODO: hide controls if participant
        "playsinline" : 1,
        "modestbranding" : 1,
        "showinfo" : 0,
        "controls" : 1
				]
	
    var stream: Stream? {
        get {
            return viewModel.stream
        }
        set {
            viewModel.stream = newValue
        }
    }
    
    var videoQueue: [Video]? {
        get {
            return viewModel.videoQueue
        }
        set {
            viewModel.videoQueue = newValue
        }
    }
	
	// TODO: Remove or move to viewModel
    fileprivate var isPlaying = false
	
    let viewModel = StreamViewModel()
    
    //accessory view shown above keyboard while chatting
    fileprivate var accessoryView: ChatTextFieldAccessoryView!

    override func viewDidLoad() {
        super.viewDidLoad()
        viewModel.delegate = self
		
        setupChatTableView()
        setupQueueTableView()
        setupPlayerView()
        setupChatTextFieldView()
        setupProfilePictures()
        setupViewForHostOrParticipant()
        setupConstraints()
		
        NotificationCenter.default.addObserver(self, selector: #selector(StreamViewController.rotated), name: NSNotification.Name.UIDeviceOrientationDidChange, object: nil)
		
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        UIView.setAnimationsEnabled(true)
    }
	
	override func viewWillDisappear(_ animated: Bool) {
		super.viewWillDisappear(animated)
		
		if isBeingDismissed {
			NotificationCenter.default.removeObserver(self)
		}
	}
	
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    

    private func setupViewForHostOrParticipant() { //TODO: player setup (don't allow participant to pause, etc)
        if viewModel.isHost { //host-- can view queue, can end stream, can invite people
            headerArrowImageView.isHidden = false
            headerViewButton.isHidden = false
            
            
            //Set bar button items and their actions programmatically
            let closeButton = UIButton(type: .custom)
            closeButton.setImage(UIImage(named: "xStream"), for: .normal)
            closeButton.frame = closeButtonFrame
            closeButton.addTarget(self, action: #selector(StreamViewController.closeTapped), for: .touchUpInside)
            let item1 = UIBarButtonItem(customView: closeButton)
            
            let profileButton = UIButton(type: .custom)
            profileButton.setImage(UIImage(named: "inviteIcon"), for: .normal)
            profileButton.frame = profileButtonFrame
            profileButton.addTarget(self, action: #selector(StreamViewController.profileTapped), for: .touchUpInside)
            let item2 = UIBarButtonItem(customView: profileButton)
            
            navigationItem.setLeftBarButtonItems([item1], animated: false)
            navigationItem.setRightBarButtonItems([item2], animated: false)
        }
        else { //participant-- cannot view queue, can't end stream, can't invite people
            headerArrowImageView.isHidden = true
            headerViewButton.isHidden = true
            
            //Set bar button items and their actions programmatically
            let closeButton = UIButton(type: .custom)
            closeButton.setImage(UIImage(named: "back_stream"), for: .normal)
            closeButton.frame = closeButtonFrame
            closeButton.addTarget(self, action: #selector(StreamViewController.closeTapped), for: .touchUpInside) //TODO: Change this to not end stream
            let item1 = UIBarButtonItem(customView: closeButton)
            
            navigationItem.setLeftBarButtonItems([item1], animated: false)
        }
        //set title
        navigationItem.title = stream?.name
    }
    
    /// Adds a textfield view above keyboard when user starts typing in chat
    private func setupChatTextFieldView() {
        //new instance of accessory view
        accessoryView = ChatTextFieldAccessoryView.instanceFromNib()
        
        //set delegates of text fields
        accessoryView.textField.delegate = self
        chatInputTextField.delegate = self
        
        //add selector to dismiss and when editing to sync up both textfields
        accessoryView.sendButton.addTarget(self, action: #selector(StreamViewController.chatInputActionTriggered), for: .touchUpInside)
        chatInputTextField.addTarget(self, action: #selector(StreamViewController.chatEditingChanged), for: [.editingChanged, .editingDidEnd])
        accessoryView.textField.addTarget(self, action: #selector(StreamViewController.accessoryViewEditingChanged), for: [.editingChanged, .editingDidEnd])
        
        //actually set accessory view
        chatInputTextField.inputAccessoryView = accessoryView
        
        
    }
    
    private func setupProfilePictures() {
        FacebookDataManager.sharedInstance.fetchProfilePictureForCurrentUser() {error, image in
            if let image = image {
                DispatchQueue.main.async {
                    self.profileImageView.image = image
                    self.accessoryView.profileImageView.image = image
                }
            }
        }
    }
    
    private func setupChatTableView() {
        chatTableView.delegate = self
        chatTableView.dataSource = self
        chatTableView.register(UINib(nibName: "ChatMessageTableViewCell", bundle: nil), forCellReuseIdentifier: "chatMessage")
        chatTableView.register(UINib(nibName: "ChatEventTableViewCell", bundle: nil), forCellReuseIdentifier: "chatEvent")
        
    }
    
    private func setupQueueTableView() {
        queueTableView.register(UINib(nibName: "VideoQueueTableViewCell", bundle: nil), forCellReuseIdentifier: "queueCell")
    }
    
    private func setupConstraints() {
        originalHeaderViewHeightConstraint = headerViewHeightConstraint.constant
        
    }
    
    private func setupPlayerView() {
        playerView.delegate = self
        //self.playerView.loadPlaylist(byVideos: ["4NFDhxhWyIw", "RTDuUiVSCo4"], index: 0, startSeconds: 0, suggestedQuality: .auto)
		if viewModel.isHost, let queue = viewModel.videoQueue, queue.count > 0 {
            updateView(forVideoWithID: queue[0].id)
			playerView.load(withVideoId: queue[0].id, playerVars: playerVars)
            viewModel.currentVideoIndex = 0
		}
		
    }
    
    
    //copy text from main screen chat input textfield to accessory view textfield when editing changes or ends
    func chatEditingChanged(textField: UITextField) {
        accessoryView.textField.text = chatInputTextField.text
        
    }
    
    //copy text from accessory view textfield to main screen chat input textfield when editing changes or ends
    func accessoryViewEditingChanged(textField: UITextField) {
        chatInputTextField.text = accessoryView.textField.text
        
    }
    
    func cancelChatTapped() {
        accessoryView.textField.resignFirstResponder()
        chatInputTextField.resignFirstResponder()
        
    }
    
    @IBAction func dismissViewTapped(_ sender: Any) {
        //dismiss view tapped, so dismiss keyboard if shown
        cancelChatTapped()
    }
    
    func rotated() {
        if UIDeviceOrientationIsLandscape(UIDevice.current.orientation) {
            playerView.frame = view.frame //make fullscreen if landscape
            mediaControllerView.isHidden = true
            print("Landscape")
        }
        
        if UIDeviceOrientationIsPortrait(UIDevice.current.orientation) {
            playerView.updateConstraintsIfNeeded()
            mediaControllerView.isHidden = false
            print("Portrait")
        }
        
    }
    
    //header tapped, so show or hide queue if host
    @IBAction func headerTapped(_ sender: Any) {
        UIView.setAnimationsEnabled(true) //fix for animations breaking
        
        if queueView.isHidden {
            headerViewHeightConstraint.constant = originalHeaderViewHeightConstraint + queueView.frame.height
            UIView.animate(withDuration: headerViewAnimationDuration, delay: 0, options: .curveEaseOut, animations: { _ in
                self.view.layoutIfNeeded()
                //rotate arrow
                self.headerArrowImageView.transform = CGAffineTransform(rotationAngle: CGFloat.pi)
            }, completion: { complete in
                self.queueView.isHidden = false
            })
        }
        else {
            self.queueView.isHidden = true
            headerViewHeightConstraint.constant = originalHeaderViewHeightConstraint
            UIView.animate(withDuration: headerViewAnimationDuration, delay: 0, options: .curveEaseOut, animations: { _ in
                self.view.layoutIfNeeded()
                //rotate arrow
                self.headerArrowImageView.transform = CGAffineTransform.identity
            }, completion: { complete in
            })
        }
    }
    
    
    func profileTapped() {
        guard let inviteVC = Utils.vcWithNameFromStoryboardWithName("inviteStream", storyboardName: "InviteStream") as? InviteStreamViewController else {
            return
        }
        inviteVC.navigationItem.title = "Invite to Stream"
        navigationController?.pushViewController(inviteVC, animated: true)
    }

    func closeTapped() {
        if viewModel.isHost {
            closeTappedAsHost()
        } else {
            closeTappedAsParticipant()
        }
    }
    
    private func closeTappedAsHost() {
        // define callback to end the stream
        let endStream = {
            self.viewModel.endStream()
            let _ = self.navigationController?.popToRootViewController(animated: true)
        }
        
        // present popup with default user profile picture
        let popup = PopupViewController.instantiate(
            titleText: stream?.name ?? "MY STREAM",
            image: #imageLiteral(resourceName: "stormtrooper_helmet"),
            messageText: stream?.name ?? "",
            descriptionText: "Would you like to end your stream?",
            primaryButtonText: "END STREAM",
            secondaryButtonText: "Cancel",
            completion: endStream
        )
        present(popup, animated: true)
        
        // update popup with user profile picture
        guard let hostFacebookID = stream?.hostFacebookID else { return }
        FacebookDataManager.sharedInstance.fetchInfoForUser(withID: hostFacebookID) { error, user in
            guard error == nil else { return }
            if let user = user {
                user.fetchProfileImage { error, image in
                    guard error == nil else { return }
                    if let image = image {
                        popup.image = image
                    }
                }
            }
        }
    }
    
    private func closeTappedAsParticipant() {
        let _ = navigationController?.popToRootViewController(animated: true)
    }

    @IBAction func addToStreamTapped(_ sender: Any) {
        guard let addVideosVC = Utils.vcWithNameFromStoryboardWithName("addVideos", storyboardName: "AddVideos") as? AddVideosViewController else {
            return
        }
        present(addVideosVC, animated: true, completion: nil)
    }
    
    
    func chatInputActionTriggered() {
        var textToSend = ""
		if let text = chatInputTextField.text {
			textToSend = text
		}
        else if let text = accessoryView.textField.text {
            textToSend = text
        }
        
        //send chat
        viewModel.send(chatMessage: textToSend)
        
        //reset textfields
        accessoryView.textField.text = nil
        chatInputTextField.text = nil
        
        //dismiss keyboard
        accessoryView.textField.resignFirstResponder()
        chatInputTextField.resignFirstResponder()
        
        //hide keyboard views
        updateView(forIsKeyboardShowing: false)
        
	}
    @IBAction func didToggleQueueEdit(_ sender: UIButton) {
        if queueTableView.isEditing {
            queueTableView.isEditing = false
            sender.setTitle("Edit", for: .normal)
        }
        else {
            queueTableView.isEditing = true
            sender.setTitle("Done", for: .normal)
        }
    }
	
	fileprivate func getVideoID(from url: URL) -> String? {
		guard let queries = url.query?.components(separatedBy: "&") else {
			return nil
		}
		for queryString in queries {
			let query = queryString.components(separatedBy: "=")
			if query.count > 1 && query[0] == "v" {
				return query[1]
			}
		}
		return nil
	}
    
    fileprivate func updateView(forVideoWithID id: String) {
        viewModel.getVideo(withID: id) {[weak self] error, video in
            if let video = video {
                DispatchQueue.main.async {
                    self?.videoTitleLabel.text = video.title
                    var subtitle = video.channelTitle
                    if let viewCount = video.viewCount {
                        subtitle += " - \(viewCount) views"
                    }
                    self?.videoSubtitleLabel.text = subtitle
                }
            }
        }
    }

}

extension StreamViewController: StreamViewModelDelegate {
	func userCountChanged(toCount count: Int) {
		userCountLabel.text = "\(count)"
	}
	
	func recieved(message: Message, for position: Int) {
            self.chatTableView.beginUpdates()
            self.chatTableView.insertRows(at: [IndexPath(row: position, section: 0)], with: .automatic)
            self.chatTableView.scrollTableViewToBottom(animated: false)
            self.chatTableView.endUpdates()
	}
	
	func recievedUpdate(forCurrentVideoID currentVideoID: String) {
		var playerID: String?
		if let playerURL = playerView.videoUrl() {
			playerID = getVideoID(from: playerURL)
		}
		if playerView.videoUrl() == nil || currentVideoID != playerID {
            updateView(forVideoWithID: currentVideoID)
			DispatchQueue.main.async { //TODO: hide controls if participant
				self.playerView.load(withVideoId: currentVideoID, playerVars: self.playerVars)
			}
		}
	}
	
	func recievedUpdate(forIsPlaying isPlaying: Bool) {
		if isPlaying && playerView.playerState() != .playing {
            DispatchQueue.main.async {
                self.playerView.playVideo()
            }
		}
		else if !isPlaying && playerView.playerState() != .paused {
            DispatchQueue.main.async {
                self.playerView.pauseVideo()
            }
		}
	}
	
	func recievedUpdate(forIsBuffering isBuffering: Bool) {
		if isBuffering && playerView.playerState() == .playing {
            DispatchQueue.main.async {
                self.playerView.pauseVideo()
            }
		}
	}
	
	func recievedUpdate(forPlaytime playtime: Float) {
		if abs(playtime - playerView.currentTime()) > viewModel.maximumDesyncTime {
            DispatchQueue.main.async {
                self.playerView.seek(toSeconds: playtime, allowSeekAhead: true)
            }
		}
	}
	
	func streamEnded() {
        playerView.pauseVideo()
        
        // present popup with default user profile picture
		let popup = PopupViewController.instantiate(
            titleText: (stream?.name ?? "").uppercased(),
            image: #imageLiteral(resourceName: "stormtrooper_helmet"),
            messageText: (stream?.name ?? "").uppercased(),
            descriptionText: "This stream has ended.",
            primaryButtonText: "OKAY",
            completion: { _ = self.navigationController?.popViewController(animated: true) }
        )
        present(popup, animated: true)
        
        // update popup with user profile picture from Facebook
        if let hostFacebookID = stream?.hostFacebookID {
            FacebookDataManager.sharedInstance.fetchInfoForUser(withID: hostFacebookID) { error, user in
                guard error == nil else { return }
                user?.fetchProfileImage { error, image in
                    guard error == nil else { return }
                    if let image = image {
                        popup.image = image
                    }
                }
            }
        }
	}
}

extension StreamViewController: UITableViewDelegate, UITableViewDataSource {
	func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if tableView.tag == chatTableTag {
            return cellFor(chatTableView: tableView, at: indexPath)
        }
        else if tableView.tag == queueTableTag {
            return cellFor(queueTableView: tableView, at: indexPath)
        }
        return UITableViewCell()
	}
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return UITableViewAutomaticDimension
    }
    
    func tableView(_ tableView: UITableView, estimatedHeightForRowAt indexPath: IndexPath) -> CGFloat {
        return estimatedChatCellHeight
    }
    
    func updateView(forIsKeyboardShowing isKeyboardShowing: Bool) {
        if isKeyboardShowing {
            visualEffectView.isHidden = false
            dismissView.isHidden = false
        }
        else {
            visualEffectView.isHidden = true
            dismissView.isHidden = true
        }
    }
    
    func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        return indexPath.row != viewModel.currentVideoIndex
    }
    
    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCellEditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete, indexPath.row != viewModel.currentVideoIndex {
            tableView.beginUpdates()
            viewModel.videoQueue?.remove(at: indexPath.row)
            tableView.deleteRows(at: [indexPath], with: .automatic)
            if viewModel.currentVideoIndex ?? 0 > indexPath.row {
                viewModel.currentVideoIndex = (viewModel.currentVideoIndex ?? 0) - 1
            }
            tableView.endUpdates()
        }
    }
	
	func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if tableView.tag == chatTableTag {
            return viewModel.messages.count //TODO: limit this to 50 or whatever performance allows
        }
        else if tableView.tag == queueTableTag {
            return viewModel.videoQueue?.count ?? 0
        }
        return 0
	}
    
    func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
        if tableView.tag == queueTableTag {
            return true
        }
        return false
    }
    
    func tableView(_ tableView: UITableView, moveRowAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) {
        guard let currentVideoIndex = viewModel.currentVideoIndex, let video = viewModel.videoQueue?.remove(at: sourceIndexPath.row) else {
            return
        }
        viewModel.videoQueue?.insert(video, at: destinationIndexPath.row)
        if sourceIndexPath.row == currentVideoIndex {
            viewModel.currentVideoIndex = destinationIndexPath.row
        }
        else if destinationIndexPath.row == currentVideoIndex {
            viewModel.currentVideoIndex = destinationIndexPath.row + (sourceIndexPath.row > destinationIndexPath.row ? 1 : -1)
        }
        // left-to-right
        else if sourceIndexPath.row < currentVideoIndex, currentVideoIndex < destinationIndexPath.row {
            viewModel.currentVideoIndex = currentVideoIndex - 1
        }
        
        // right-to-left
        else if sourceIndexPath.row > currentVideoIndex, currentVideoIndex > destinationIndexPath.row {
            viewModel.currentVideoIndex = currentVideoIndex + 1
        }
    }
    
    func tableView(_ tableView: UITableView, targetIndexPathForMoveFromRowAt sourceIndexPath: IndexPath, toProposedIndexPath proposedDestinationIndexPath: IndexPath) -> IndexPath {
        return proposedDestinationIndexPath
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if viewModel.currentVideoIndex != indexPath.row {
            viewModel.currentVideoIndex = indexPath.row
            playerView.cueVideo(byId: viewModel.videoQueue?[indexPath.row].id ?? "", startSeconds: 0, suggestedQuality: .default)
            playerView.playVideo()
        }
    }
	
    private func cellFor(chatTableView tableView: UITableView, at indexPath: IndexPath) -> UITableViewCell {
        let messageCell = tableView.dequeueReusableCell(withIdentifier: "chatMessage") as? ChatMessageTableViewCell
        let eventCell = tableView.dequeueReusableCell(withIdentifier: "chatEvent") as? ChatEventTableViewCell
        
        let message = viewModel.messages[indexPath.row]
        
        FacebookDataManager.sharedInstance.fetchInfoForUser(withID: message.subjectID) { error, user in
            if let message = message as? ChatMessage {
                DispatchQueue.main.async {
                    messageCell?.messageLabel.text = message.content
                    messageCell?.nameLabel.text = user?.name
                }
            }
            else if let message = message as? ParticipantMessage {
                DispatchQueue.main.async {
                    eventCell?.messageLabel.text = message.isJoining ? " joined the stream." : " left the stream."
                    eventCell?.nameLabel.text = user?.name
                }
            }
            user?.fetchProfileImage { error, image in
                DispatchQueue.main.async {
                    messageCell?.profileImageView.image = image
                    eventCell?.profileImageView.image = image
                }
            }
        }
        
        //return messageCell ?? eventCell ?? UITableViewCell()
        if message is ChatMessage, let messageCell = messageCell {
            return messageCell
        }
        else if message is ParticipantMessage, let eventCell = eventCell {
            return eventCell
        }
        else {
            return UITableViewCell()
        }
    }
    
	private func cellFor(queueTableView tableView: UITableView, at indexPath: IndexPath) -> UITableViewCell {
        guard
        let cell = tableView.dequeueReusableCell(withIdentifier: "queueCell") as? VideoQueueTableViewCell,
        let video = viewModel.videoQueue?[indexPath.row] else {
            return UITableViewCell()
        }
        cell.titleLabel.text = video.title
        cell.channelTitleLabel.text = video.channelTitle
        YouTubeDataManager.sharedInstance.getThumbnailForVideo(with: video.mediumThumbnailURL) {error, image in
            if let image = image {
                cell.thumbnailImageView.image = image
            }
        }
        if indexPath.row == viewModel.currentVideoIndex {
            cell.isSelected = true
        }
        cell.selectionStyle = .none
        return cell
    }
}

extension StreamViewController: YTPlayerViewDelegate {
    func playerView(_ playerView: YTPlayerView, didPlayTime playTime: Float) {
		if viewModel.isHost {
			viewModel.send(currentPlayTime: playerView.currentTime())
		}
        print("Current Time: \(playerView.currentTime()) out of \(playerView.duration()) - Video Loaded \(playerView.videoLoadedFraction() * 100)%")
    }
    
    func playerView(_ playerView: YTPlayerView, receivedError error: YTPlayerError) {
        //error received
    }
    
    func playerView(_ playerView: YTPlayerView, didChangeTo quality: YTPlaybackQuality) {
        //quality changed
    }
    
    func playerViewDidBecomeReady(_ playerView: YTPlayerView) {
        // player ready --
        // could show loading before this is called, and hide loading when this is called
        print("player ready!")
		if !viewModel.isHost {
			playerView.playVideo()
		}
    }
    
//    func playerViewPreferredInitialLoading(_ playerView: YTPlayerView) -> UIView? {
//        //return loading view to be shown before player becomes ready
//        let loadingView = UIView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
//        loadingView.backgroundColor = UIColor.red
//        return loadingView
//    }
    
//    func playerViewPreferredWebViewBackgroundColor(_ playerView: YTPlayerView) -> UIColor {
//        return UIColor.clear
//    }
    
    
    func playerView(_ playerView: YTPlayerView, didChangeTo state: YTPlayerState) {
        switch (state) {
        case .paused:
            isPlaying = false
			if viewModel.isHost {
				viewModel.send(playState: false)
			}
            break
        case .buffering:
			if viewModel.isHost, let url = playerView.videoUrl(), let id = getVideoID(from: url) {
                updateView(forVideoWithID: id)
				viewModel.send(currentVideoID: id)
				viewModel.send(isBuffering: true)
			}
        case .playing:
            isPlaying = true
			if viewModel.isHost {
				viewModel.send(isBuffering: false)
				viewModel.send(playState: true)
			}
			else if !viewModel.hostPlaying {
				playerView.pauseVideo()
			}
            break
        case .ended:
            if viewModel.isHost, let queue = viewModel.videoQueue, var queueIndex = viewModel.currentVideoIndex {
                queueIndex = queueIndex < queue.count - 1 ? queueIndex + 1 : 0
                playerView.cueVideo(byId: queue[queueIndex].id, startSeconds: 0, suggestedQuality: .default)
                viewModel.currentVideoIndex = queueIndex
                playerView.playVideo()
            }
            break
        case .queued:
            break
        case .unknown:
            break
        case .unstarted:
            break
        }
    }
    
}

extension StreamViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        chatInputActionTriggered() //send the chat
        return true
    }
    
    func textFieldShouldBeginEditing(_ textField: UITextField) -> Bool {
        return true
    }
    
    func textFieldDidBeginEditing(_ textField: UITextField) {
        UIView.setAnimationsEnabled(true) //fix for animations breaking
        updateView(forIsKeyboardShowing: true)
    }
    
    func textFieldDidEndEditing(_ textField: UITextField) {
        updateView(forIsKeyboardShowing: false)
    }
    
    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {

        
        return true
    }
}
