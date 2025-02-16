import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

void main() => runApp(P2PChatApp());

/// Represents a single chat message.
class ChatMessage {
  final String text;
  final bool isSentByMe;
  ChatMessage({required this.text, required this.isSentByMe});
}

/// Encapsulates a WebRTC conversation with one peer.
class Conversation {
  final String peerId;
  RTCPeerConnection? connection;
  RTCDataChannel? dataChannel;
  Completer<void>? dataChannelOpenedCompleter;
  List<ChatMessage> messages = [];

  // For ICE candidates received before the remote description is set.
  bool remoteDescriptionSet = false;
  final List<RTCIceCandidate> pendingCandidates = [];

  Conversation(this.peerId);

  /// Initializes the connection.
  /// [initiator] should be true if we are starting the conversation.
  /// [onMessageReceived] is called when a new message arrives.
  /// [sendSignal] is a callback to send signaling data.
  Future<void> initialize({
    required bool initiator,
    required Function(String) onMessageReceived,
    required Function(Map<String, dynamic>) sendSignal,
  }) async {
    connection = await createPeerConnection({
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
      ]
    });
    connection!.onIceCandidate = (candidate) {
      // Send each ICE candidate via signaling.
      sendSignal({'candidate': candidate.toMap()});
    };
    connection!.onDataChannel = (channel) {
      dataChannel = channel;
      _setupDataChannel(onMessageReceived);
    };

    // If we're the initiator, create our own data channel.
    if (initiator) {
      dataChannel =
          await connection!.createDataChannel("chat", RTCDataChannelInit());
      _setupDataChannel(onMessageReceived);
    }
  }

  void _setupDataChannel(Function(String) onMessageReceived) {
    dataChannelOpenedCompleter = Completer<void>();
    dataChannel!.onMessage = (msg) {
      onMessageReceived(msg.text);
      messages.add(ChatMessage(text: msg.text, isSentByMe: false));
    };
    dataChannel!.onDataChannelState = (state) {
      if (state == RTCDataChannelState.RTCDataChannelOpen) {
        dataChannelOpenedCompleter?.complete();
      }
    };
  }

  Future<RTCSessionDescription> createOffer() async {
    RTCSessionDescription offer = await connection!.createOffer();
    await connection!.setLocalDescription(offer);
    return offer;
  }

  Future<RTCSessionDescription> createAnswer() async {
    RTCSessionDescription answer = await connection!.createAnswer();
    await connection!.setLocalDescription(answer);
    return answer;
  }

  Future<void> setRemoteDescription(Map<String, dynamic> sdpData) async {
    RTCSessionDescription sdp =
        RTCSessionDescription(sdpData['sdp'], sdpData['type']);
    await connection!.setRemoteDescription(sdp);
    remoteDescriptionSet = true;
    // Add any queued ICE candidates.
    for (var candidate in pendingCandidates) {
      await connection!.addCandidate(candidate);
    }
    pendingCandidates.clear();
  }

  Future<void> addCandidate(Map<String, dynamic> candidateData) async {
    RTCIceCandidate candidate = RTCIceCandidate(
      candidateData['candidate'],
      candidateData['sdpMid'],
      candidateData['sdpMLineIndex'] as int?,
    );
    if (remoteDescriptionSet) {
      await connection!.addCandidate(candidate);
    } else {
      pendingCandidates.add(candidate);
    }
  }
}

/// Manages signaling and multiple conversations.
class SignalingManager {
  final String url;
  late WebSocketChannel _channel;
  String clientId = "";
  Function(String)? onLocalId;

  // Map peerId -> Conversation
  Map<String, Conversation> conversations = {};

  SignalingManager(this.url);

  void connect() {
    _channel = WebSocketChannel.connect(Uri.parse(url));
    _channel.stream.listen((message) {
      var data = jsonDecode(message);
      print("DEBUG: Received message: $data");
      switch (data['type']) {
        case 'welcome':
          clientId = data['id'];
          if (onLocalId != null) onLocalId!(clientId);
          print("DEBUG: Client ID set to: $clientId");
          break;
        case 'signal':
          String from = data['from'];
          Map<String, dynamic> signalData = data['data'];
          // Retrieve or create the conversation.
          Conversation conv = conversations[from] ?? Conversation(from);
          conversations[from] = conv;

          // If an SDP offer is received, we are the receiver.
          if (signalData.containsKey('sdp')) {
            String sdpType = signalData['sdp']['type'];
            if (sdpType == 'offer') {
              // Initialize conversation as receiver.
              conv
                  .initialize(
                initiator: false,
                onMessageReceived: (msg) {
                  // Notify UI that a new message arrived.
                  _notifyUpdate();
                },
                sendSignal: (signal) {
                  sendSignalMessage(from, signal);
                },
              )
                  .then((_) async {
                await conv.setRemoteDescription(signalData['sdp']);
                RTCSessionDescription answer = await conv.createAnswer();
                sendSignalMessage(from, {'sdp': answer.toMap()});
              });
            } else if (sdpType == 'answer') {
              // Answer to our offer.
              conv.setRemoteDescription(signalData['sdp']);
            }
          }
          // ICE candidate
          if (signalData.containsKey('candidate')) {
            conv.addCandidate(signalData['candidate']);
          }
          break;
        default:
          print("DEBUG: Unhandled message type: ${data['type']}");
      }
      _notifyUpdate();
    });
  }

  void sendSignalMessage(String target, Map<String, dynamic> data) {
    _channel.sink.add(jsonEncode({
      'type': 'signal',
      'target': target,
      'from': clientId,
      'data': data,
    }));
    print("DEBUG: Sent signal to $target with data $data");
  }

  /// Initiates a conversation with [target] as the initiator.
  Future<Conversation> startConversation(
      String target, Function(String) onMessageReceived) async {
    if (conversations.containsKey(target)) return conversations[target]!;
    Conversation conv = Conversation(target);
    conversations[target] = conv;
    await conv.initialize(
      initiator: true,
      onMessageReceived: (msg) {
        onMessageReceived(msg);
        _notifyUpdate();
      },
      sendSignal: (signal) {
        sendSignalMessage(target, signal);
      },
    );
    RTCSessionDescription offer = await conv.createOffer();
    sendSignalMessage(target, {'sdp': offer.toMap()});
    return conv;
  }

  /// Sends a text message in the conversation with [target].
  Future<void> sendMessage(String target, String msg) async {
    if (!conversations.containsKey(target)) return;
    Conversation conv = conversations[target]!;
    if (conv.dataChannel == null) return;
    await conv.dataChannelOpenedCompleter?.future;
    conv.dataChannel!.send(RTCDataChannelMessage(msg));
    conv.messages.add(ChatMessage(text: msg, isSentByMe: true));
    _notifyUpdate();
  }

  // A simple mechanism to trigger UI updates.
  VoidCallback? _updateCallback;
  void registerUpdateCallback(VoidCallback cb) {
    _updateCallback = cb;
  }

  void _notifyUpdate() {
    if (_updateCallback != null) _updateCallback!();
  }
}

/// The main UI.
class P2PChatApp extends StatefulWidget {
  const P2PChatApp({super.key});
  @override
  P2PChatAppState createState() => P2PChatAppState();
}

class P2PChatAppState extends State<P2PChatApp> {
  final TextEditingController _targetIdController = TextEditingController();
  final TextEditingController _messageController = TextEditingController();
  late SignalingManager signalingManager;
  String? selectedPeerId;

  @override
  void initState() {
    super.initState();
    signalingManager = SignalingManager('ws://localhost:8080');
    signalingManager.onLocalId = (id) => setState(() {});
    signalingManager.registerUpdateCallback(() {
      setState(() {});
    });
    signalingManager.connect();
  }

  /// Initiate a conversation with the entered peer ID.
  void _connectToPeer() async {
    String targetId = _targetIdController.text;
    if (targetId.isEmpty) return;
    await signalingManager.startConversation(targetId, (msg) {
      setState(() {}); // refresh UI when a new message arrives.
    });
    setState(() {
      selectedPeerId = targetId;
    });
  }

  /// Sends a message in the active conversation.
  void _sendMessage() async {
    if (selectedPeerId == null) return;
    String msg = _messageController.text;
    if (msg.isEmpty) return;
    await signalingManager.sendMessage(selectedPeerId!, msg);
    setState(() {
      _messageController.clear();
    });
  }

  /// Builds a message bubble.
  Widget _buildMessageBubble(ChatMessage msg) {
    return Align(
      alignment: msg.isSentByMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: msg.isSentByMe ? Colors.blue[200] : Colors.grey[300],
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(msg.text),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Get messages for the selected conversation.
    List<ChatMessage> messages = [];
    if (selectedPeerId != null &&
        signalingManager.conversations.containsKey(selectedPeerId)) {
      messages = signalingManager.conversations[selectedPeerId]!.messages;
    }
    return MaterialApp(
      title: "P2P Chat (${signalingManager.clientId})",
      home: Scaffold(
        appBar: AppBar(title: Text("P2P Chat (${signalingManager.clientId})")),
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              // Peer connection controls.
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _targetIdController,
                      decoration: InputDecoration(labelText: "Enter Peer ID"),
                    ),
                  ),
                  ElevatedButton(
                    onPressed: _connectToPeer,
                    child: Text("Connect"),
                  ),
                ],
              ),
              // Dropdown for active conversations.
              DropdownButton<String>(
                hint: Text("Select Conversation"),
                value: selectedPeerId,
                items: signalingManager.conversations.keys.map((peerId) {
                  return DropdownMenuItem<String>(
                    value: peerId,
                    child: Text(peerId),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    selectedPeerId = value;
                  });
                },
              ),
              // Display conversation messages.
              Expanded(
                child: ListView(
                  children: messages.map(_buildMessageBubble).toList(),
                ),
              ),
              // Message input field and Send button.
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      decoration: InputDecoration(labelText: "Type a message"),
                    ),
                  ),
                  ElevatedButton(
                    onPressed: _sendMessage,
                    child: Text("Send"),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
