import AmazonIVSBroadcast
import AVFoundation
import Flutter
import UIKit

// MARK: - Participant model (mirrors Android StageParticipant)

final class StageParticipantModel {
  let isLocal: Bool
  var participantId: String?
  var publishState: IVSParticipantPublishState = .notPublished
  var subscribeState: IVSParticipantSubscribeState = .notSubscribed
  var streams: [IVSStageStream] = []

  init(isLocal: Bool, participantId: String?) {
    self.isLocal = isLocal
    self.participantId = participantId
  }

  var stableID: String {
    isLocal ? "LocalUser" : (participantId ?? "")
  }
}

// MARK: - Collection adapter

final class ParticipantIOSAdapter: NSObject, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
  private var participants: [StageParticipantModel] = []
  private weak var collectionView: UICollectionView?

  func attach(_ collectionView: UICollectionView) {
    collectionView.dataSource = self
    collectionView.delegate = self
    collectionView.register(ParticipantCell.self, forCellWithReuseIdentifier: ParticipantCell.reuseId)
    collectionView.backgroundColor = .black
    self.collectionView = collectionView
  }

  func notifyDataSetChanged() {
    DispatchQueue.main.async { [weak self] in
      self?.collectionView?.reloadData()
      self?.collectionView?.collectionViewLayout.invalidateLayout()
    }
  }

  func participantJoined(_ participant: StageParticipantModel) {
    participants.append(participant)
    notifyDataSetChanged()
  }

  func participantLeft(participantId: String) {
    if let index = participants.firstIndex(where: { $0.participantId == participantId }) {
      participants.remove(at: index)
      notifyDataSetChanged()
    }
  }

  func participantUpdated(participantId: String?, update: (StageParticipantModel) -> Void) {
    guard let index = participants.firstIndex(where: { $0.participantId == participantId }) else { return }
    update(participants[index])
    notifyDataSetChanged()
  }

  func updateLocalParticipant(update: (StageParticipantModel) -> Void) {
    guard let index = participants.firstIndex(where: { $0.isLocal }) else { return }
    update(participants[index])
    notifyDataSetChanged()
  }

  func ensureLocalParticipant() {
    if participants.contains(where: { $0.isLocal }) { return }
    participants.insert(StageParticipantModel(isLocal: true, participantId: nil), at: 0)
    notifyDataSetChanged()
  }

  func removeLocalParticipant() {
    if let index = participants.firstIndex(where: { $0.isLocal }) {
      participants.remove(at: index)
      notifyDataSetChanged()
    }
  }

  func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
    participants.count
  }

  func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath)
    -> UICollectionViewCell
  {
    let cell = collectionView.dequeueReusableCell(withReuseIdentifier: ParticipantCell.reuseId, for: indexPath)
      as! ParticipantCell
    cell.bind(participants[indexPath.item])
    return cell
  }

  func collectionView(
    _ collectionView: UICollectionView,
    layout collectionViewLayout: UICollectionViewLayout,
    sizeForItemAt indexPath: IndexPath
  ) -> CGSize {
    let count = max(participants.count, 1)
    var totalH = collectionView.bounds.height
    // Flutter often lays out the platform view before the collection view has a non-zero height.
    if totalH < 44 {
      totalH = collectionView.superview?.bounds.height
        ?? UIScreen.main.bounds.height * 0.55
    }
    let h = floor(totalH / CGFloat(count))
    return CGSize(width: max(collectionView.bounds.width, 1), height: max(h, 160))
  }
}

// MARK: - Cell

private final class ParticipantCell: UICollectionViewCell {
  static let reuseId = "ParticipantCell"

  private let previewContainer = UIView()
  private let labelsStack = UIStackView()
  private let idLabel = UILabel()
  private let publishLabel = UILabel()
  private let subscribeLabel = UILabel()
  private let videoMutedLabel = UILabel()
  private let audioMutedLabel = UILabel()
  private let audioLevelLabel = UILabel()
  private var boundImageStream: IVSStageStream?
  private var audioDeviceUrn: String?

  override init(frame: CGRect) {
    super.init(frame: frame)
    contentView.backgroundColor = UIColor(white: 0.08, alpha: 1)
    previewContainer.backgroundColor = .black
    previewContainer.clipsToBounds = true
    previewContainer.translatesAutoresizingMaskIntoConstraints = false
    [idLabel, publishLabel, subscribeLabel, videoMutedLabel, audioMutedLabel, audioLevelLabel].forEach {
      $0.textColor = .white
      $0.font = .systemFont(ofSize: 11)
      $0.numberOfLines = 0
      labelsStack.addArrangedSubview($0)
    }
    labelsStack.axis = .vertical
    labelsStack.spacing = 2
    labelsStack.alignment = .fill
    labelsStack.translatesAutoresizingMaskIntoConstraints = false
    contentView.addSubview(previewContainer)
    contentView.addSubview(labelsStack)
    NSLayoutConstraint.activate([
      labelsStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 6),
      labelsStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -6),
      labelsStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),

      previewContainer.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
      previewContainer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 6),
      previewContainer.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -6),
      previewContainer.bottomAnchor.constraint(equalTo: labelsStack.topAnchor, constant: -6),
    ])
  }

  required init?(coder: NSCoder) { fatalError("init(coder:)") }

  func bind(_ participant: StageParticipantModel) {
    let participantIdText: String =
      participant.isLocal
      ? "You (\(participant.participantId ?? "Disconnected"))"
      : (participant.participantId ?? "")
    idLabel.text = participantIdText
    publishLabel.text = String(describing: participant.publishState)
    subscribeLabel.text = String(describing: participant.subscribeState)

    let newImageStream = participant.streams.first { $0.device is IVSImageDevice }
    if let img = newImageStream {
      videoMutedLabel.text = img.isMuted ? "Video muted" : "Video not muted"
    } else {
      videoMutedLabel.text = "No video stream"
    }

    let newAudioStream = participant.streams.first { $0.device is IVSAudioDevice }
    if let au = newAudioStream {
      audioMutedLabel.text = au.isMuted ? "Audio muted" : "Audio not muted"
    } else {
      audioMutedLabel.text = "No audio stream"
    }

    if newImageStream == nil {
      if previewContainer.subviews.isNotEmpty || boundImageStream != nil {
        previewContainer.subviews.forEach { $0.removeFromSuperview() }
      }
      boundImageStream = nil
    } else {
      let mustReattach = newImageStream !== boundImageStream || previewContainer.subviews.isEmpty
      if mustReattach {
        previewContainer.subviews.forEach { $0.removeFromSuperview() }
        boundImageStream = newImageStream
        if let imageDevice = newImageStream?.device as? IVSImageDevice {
          do {
            let preview = try imageDevice.previewView(with: .fill)
            preview.translatesAutoresizingMaskIntoConstraints = false
            previewContainer.addSubview(preview)
            NSLayoutConstraint.activate([
              preview.leadingAnchor.constraint(equalTo: previewContainer.leadingAnchor),
              preview.trailingAnchor.constraint(equalTo: previewContainer.trailingAnchor),
              preview.topAnchor.constraint(equalTo: previewContainer.topAnchor),
              preview.bottomAnchor.constraint(equalTo: previewContainer.bottomAnchor),
            ])
            preview.setNeedsLayout()
          } catch {}
        }
      }
    }
    previewContainer.setNeedsLayout()

    let urn = (newAudioStream?.device as? IVSDevice)?.descriptor().urn
    if urn != audioDeviceUrn {
      if let audioDevice = newAudioStream?.device as? IVSAudioDevice {
        audioDevice.setStatsCallback { stats in
          DispatchQueue.main.async { [weak self] in
            self?.audioLevelLabel.text = "Audio Level: \(Int(stats.rms)) dB"
          }
        }
      }
    }
    audioDeviceUrn = urn
  }
}

private extension Array {
  var isNotEmpty: Bool { !isEmpty }
}

// MARK: - Stage controller

final class IvsStageController: NSObject, IVSStageStrategy, IVSStageRenderer, IVSErrorDelegate {
  let participantAdapter = ParticipantIOSAdapter()

  /// Set by [AwsIvsRealtimePlugin] when the Dart side listens to [EventChannel] `stage_events`.
  var eventSink: FlutterEventSink?

  private let mainQueue = DispatchQueue.main
  private var deviceDiscovery: IVSDeviceDiscovery?
  private var stage: IVSStage?
  private var streams: [IVSLocalStageStream] = []
  private var publishEnabled = true
  private var connectionState: IVSStageConnectionState = .disconnected
  private var wasConnectedThisSession = false
  private var suppressDisconnectEvent = false
  private var pendingJoinToken: String?
  private var pendingJoinResult: FlutterResult?

  override init() {
    super.init()
    deviceDiscovery = IVSDeviceDiscovery()
  }

  func setPublishEnabled(_ enabled: Bool) {
    mainQueue.async { [weak self] in
      guard let self else { return }
      let changed = publishEnabled != enabled
      publishEnabled = enabled
      stage?.refreshStrategy()
      if !changed { return }
      if enabled {
        permissionGranted()
      } else {
        participantAdapter.updateLocalParticipant { $0.streams.removeAll() }
        participantAdapter.removeLocalParticipant()
      }
    }
  }

  func joinOrLeave(token: String, result: @escaping FlutterResult) {
    mainQueue.async { [weak self] in
      guard let self else { return }
      if connectionState != .disconnected {
        suppressDisconnectEvent = true
        leaveInternal()
        result(nil)
        return
      }
      if token.isEmpty {
        result(
          FlutterError(code: "INVALID_ARGUMENT", message: "Empty token", details: nil))
        return
      }
      pendingJoinToken = token
      pendingJoinResult = result
      requestJoinPermissions(publish: publishEnabled) { [weak self] ok in
        guard let self else { return }
        if !ok {
          pendingJoinResult?(
            FlutterError(
              code: "PERMISSION_DENIED",
              message: "Microphone (and camera if publishing) permission is required.",
              details: nil))
          pendingJoinToken = nil
          pendingJoinResult = nil
          return
        }
        if performJoin(token: token) {
          finishJoinSuccess()
        }
      }
    }
  }

  private func finishJoinSuccess() {
    pendingJoinResult?(nil)
    pendingJoinToken = nil
    pendingJoinResult = nil
  }

  private func requestJoinPermissions(publish: Bool, completion: @escaping (Bool) -> Void) {
    if !publish {
      AVAudioSession.sharedInstance().requestRecordPermission { ok in
        self.mainQueue.async { completion(ok) }
      }
      return
    }
    AVAudioSession.sharedInstance().requestRecordPermission { micOk in
      guard micOk else {
        self.mainQueue.async { completion(false) }
        return
      }
      AVCaptureDevice.requestAccess(for: .video) { videoOk in
        self.mainQueue.async { completion(videoOk) }
      }
    }
  }

  func refreshStageBindings() {
    mainQueue.async { [weak self] in
      guard let self else { return }
      stage?.refreshStrategy()
      participantAdapter.notifyDataSetChanged()
    }
  }

  func setLocalStreamMuted(micMuted: Bool, cameraMuted: Bool) {
    mainQueue.async { [weak self] in
      guard let self else { return }
      for stream in streams {
        if stream.device is IVSMicrophone {
          stream.setMuted(micMuted)
        } else if stream.device is IVSCamera || stream.device is IVSImageDevice {
          stream.setMuted(cameraMuted)
        }
      }
    }
  }

  func leave() {
    mainQueue.async { [weak self] in
      self?.suppressDisconnectEvent = true
      self?.leaveInternal()
    }
  }

  private func leaveInternal() {
    stage?.leave()
  }

  func releaseStage() {
    mainQueue.async { [weak self] in
      guard let self else { return }
      suppressDisconnectEvent = true
      stage?.leave()
      stage = nil
    }
  }

  @discardableResult
  private func performJoin(token: String) -> Bool {
    do {
      stage?.leave()
      stage = nil
      // Match Android: rebuild local streams after the previous stage is gone so camera
      // previews are not created while the old session still holds capture.
      permissionGranted()
      if publishEnabled {
        IVSStageAudioManager.sharedInstance().setPreset(.videoChat)
      }
      let newStage = try IVSStage(token: token, strategy: self)
      newStage.errorDelegate = self
      newStage.addRenderer(self)
      try newStage.join()
      stage = newStage
      mainQueue.async { [weak self] in
        guard let self, stage === newStage else { return }
        newStage.refreshStrategy()
        participantAdapter.notifyDataSetChanged()
      }
      return true
    } catch {
      pendingJoinResult?(
        FlutterError(code: "JOIN_FAILED", message: error.localizedDescription, details: nil))
      pendingJoinToken = nil
      pendingJoinResult = nil
      return false
    }
  }

  fileprivate func permissionGranted() {
    guard let discovery = deviceDiscovery else { return }
    streams.removeAll()
    if publishEnabled {
      let devices = discovery.listLocalDevices()
      if let camera = devices.compactMap({ $0 as? IVSCamera }).first {
        let sources = camera.listAvailableInputSources()
        if let front = sources.first(where: { $0.position == .front }) {
          camera.setPreferredInputSource(front)
        } else if let first = sources.first {
          camera.setPreferredInputSource(first)
        }
        streams.append(IVSLocalStageStream(device: camera))
      }
      let mics = devices.compactMap { $0 as? IVSMicrophone }
      if let mic = mics.first(where: { $0.descriptor().isDefault }) ?? mics.first {
        streams.append(IVSLocalStageStream(device: mic))
      }
      participantAdapter.ensureLocalParticipant()
      participantAdapter.updateLocalParticipant {
        $0.streams.removeAll()
        $0.streams.append(contentsOf: streams)
      }
    } else {
      participantAdapter.updateLocalParticipant { $0.streams.removeAll() }
      participantAdapter.removeLocalParticipant()
    }
    stage?.refreshStrategy()
  }

  // MARK: IVSStageStrategy

  func stage(_ stage: IVSStage, streamsToPublishForParticipant participant: IVSParticipantInfo) -> [IVSLocalStageStream] {
    publishEnabled ? streams : []
  }

  func stage(_ stage: IVSStage, shouldPublishParticipant participant: IVSParticipantInfo) -> Bool {
    publishEnabled
  }

  func stage(_ stage: IVSStage, shouldSubscribeToParticipant participant: IVSParticipantInfo) -> IVSStageSubscribeType {
    .audioVideo
  }

  // MARK: IVSStageRenderer

  func stage(_ stage: IVSStage, didChange connectionState: IVSStageConnectionState, withError error: Error?) {
    self.connectionState = connectionState
    if connectionState == .connected {
      wasConnectedThisSession = true
      mainQueue.async { [weak self] in
        guard let self, self.stage === stage else { return }
        stage.refreshStrategy()
        participantAdapter.notifyDataSetChanged()
      }
    } else if connectionState == .disconnected {
      let shouldEmit = wasConnectedThisSession && !suppressDisconnectEvent
      wasConnectedThisSession = false
      suppressDisconnectEvent = false
      if shouldEmit {
        let sink = eventSink
        mainQueue.async {
          sink?(["event": "disconnected"])
        }
      }
    }
  }

  func stage(_ stage: IVSStage, participantDidJoin participant: IVSParticipantInfo) {
    if participant.isLocal {
      if !publishEnabled { return }
      participantAdapter.ensureLocalParticipant()
      participantAdapter.updateLocalParticipant { $0.participantId = participant.participantId }
    } else {
      participantAdapter.participantJoined(
        StageParticipantModel(isLocal: false, participantId: participant.participantId))
    }
  }

  func stage(_ stage: IVSStage, participantDidLeave participant: IVSParticipantInfo) {
    if participant.isLocal {
      if publishEnabled {
        participantAdapter.participantUpdated(participantId: participant.participantId) {
          $0.participantId = nil
        }
      }
    } else {
      participantAdapter.participantLeft(participantId: participant.participantId)
    }
  }

  func stage(_ stage: IVSStage, participant: IVSParticipantInfo, didChange publishState: IVSParticipantPublishState) {
    participantAdapter.participantUpdated(participantId: participant.participantId) {
      $0.publishState = publishState
    }
  }

  func stage(_ stage: IVSStage, participant: IVSParticipantInfo, didChange subscribeState: IVSParticipantSubscribeState) {
    participantAdapter.participantUpdated(participantId: participant.participantId) {
      $0.subscribeState = subscribeState
    }
  }

  func stage(_ stage: IVSStage, participant: IVSParticipantInfo, didAdd streams: [IVSStageStream]) {
    if participant.isLocal { return }
    participantAdapter.participantUpdated(participantId: participant.participantId) {
      $0.streams.append(contentsOf: streams)
    }
  }

  func stage(_ stage: IVSStage, participant: IVSParticipantInfo, didRemove removedStreams: [IVSStageStream]) {
    if participant.isLocal { return }
    participantAdapter.participantUpdated(participantId: participant.participantId) { p in
      for r in removedStreams {
        if let idx = p.streams.firstIndex(where: { $0 === r }) {
          p.streams.remove(at: idx)
        }
      }
    }
  }

  func stage(_ stage: IVSStage, participant: IVSParticipantInfo, didChangeMutedStreams streams: [IVSStageStream]) {
    if participant.isLocal { return }
    participantAdapter.participantUpdated(participantId: participant.participantId) { _ in }
  }

  // MARK: IVSErrorDelegate

  func source(_ source: IVSErrorSource, didEmitError error: Error) {
    mainQueue.async { [weak self] in
      guard let self else { return }
      guard let st = self.stage, (source as AnyObject) === (st as AnyObject) else { return }
      if wasConnectedThisSession && !suppressDisconnectEvent {
        wasConnectedThisSession = false
        eventSink?(["event": "disconnected"])
      }
    }
  }
}

// MARK: - Collection view (Flutter platform views often get 0 height on first layout pass)

private final class IvsStageCollectionView: UICollectionView {
  private var lastLayoutHeight: CGFloat = -1

  override func layoutSubviews() {
    super.layoutSubviews()
    let h = bounds.height
    guard h > 10 else { return }
    if abs(h - lastLayoutHeight) > 0.5 {
      lastLayoutHeight = h
      collectionViewLayout.invalidateLayout()
    }
  }
}

// MARK: - Platform view

final class IvsStageViewFactory: NSObject, FlutterPlatformViewFactory {
  private let controller: IvsStageController

  init(controller: IvsStageController) {
    self.controller = controller
  }

  func createArgsCodec() -> (FlutterMessageCodec & NSObjectProtocol) {
    FlutterStandardMessageCodec.sharedInstance()
  }

  func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
    IvsStagePlatformView(frame: frame, controller: controller)
  }
}

private final class IvsStagePlatformView: NSObject, FlutterPlatformView {
  private let root: UIView

  init(frame: CGRect, controller: IvsStageController) {
    let layout = UICollectionViewFlowLayout()
    layout.minimumLineSpacing = 0
    layout.minimumInteritemSpacing = 0
    layout.scrollDirection = .vertical
    let cv = IvsStageCollectionView(frame: frame, collectionViewLayout: layout)
    cv.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    cv.alwaysBounceVertical = false
    cv.showsVerticalScrollIndicator = false
    cv.backgroundColor = .black
    controller.participantAdapter.attach(cv)
    root = cv
    super.init()
  }

  func view() -> UIView { root }
}
