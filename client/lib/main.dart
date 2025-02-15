import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'dart:async';

void main() => runApp(P2PChatApp());

class P2PChatApp extends StatefulWidget {
  const P2PChatApp({super.key});

  @override
  _P2PChatAppState createState() => _P2PChatAppState();
}

class _P2PChatAppState extends State<P2PChatApp> {
  final TextEditingController _targetIdController = TextEditingController();
  final TextEditingController _messageController = TextEditingController();
  late WebSocketChannel _channel;
  RTCPeerConnection? _peerConnection;
  RTCDataChannel? _dataChannel;
  String _clientId = '';
  final bool _peerConnected = false;
  bool _isConnecting = false;
  bool _isDataChannelOpen = false;
  Completer<void>? _dataChannelOpenedCompleter;
  final List<String> _messages = [];
  final String? _clientRole = "A";

  bool _remoteDescriptionSet = false;
  final List<RTCIceCandidate> _pendingCandidates = [];

  @override
  void initState() {
    super.initState();
    _connectToSignalingServer();
  }

  void _connectToSignalingServer() {
    _channel = WebSocketChannel.connect(Uri.parse('ws://localhost:8080'));
    _channel.stream.listen((message) {
      var data = jsonDecode(message);
      print("DEBUG: Received message: $data");
      switch (data['type']) {
        case 'welcome':
          setState(() {
            _clientId = data['id'];
          });
          print("DEBUG: Client ID set to: $_clientId");
          break;
        case 'signal':
          _handleSignal(data['from'], data['data']);
          break;
        default:
          print("DEBUG: Unhandled message type: ${data['type']}");
      }
    });
  }

  void _createPeerConnection() async {
    setState(() {
      _isConnecting = true;
    });

    print("DEBUG: Creating peer connection...");
    _peerConnection = await createPeerConnection({
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'}
      ]
    });

    print("DEBUG: PeerConnection created.");

    _peerConnection!.onIceCandidate = (candidate) {
      print("DEBUG: ICE Candidate found: ${candidate.toMap()}");
      _sendSignal({'candidate': candidate.toMap()});
    };

    _peerConnection!.onDataChannel = (channel) {
      print("DEBUG: onDataChannel callback triggered.");
      _dataChannel = channel;
      _setupDataChannel();
    };

    if (_clientRole == "A") {
      print("DEBUG: Creating data channel for Client A.");
      _dataChannel = await _peerConnection!
          .createDataChannel("chat", RTCDataChannelInit());
      print("DEBUG: Data channel created (Client A).");
      _setupDataChannel();
      RTCSessionDescription offer = await _peerConnection!.createOffer();
      await _peerConnection!.setLocalDescription(offer);
      _sendSignal({'sdp': offer.toMap()});
    } else {
      print("DEBUG: Waiting for offer from Client A (role B).");
    }
  }

  void _handleSignal(String from, Map<String, dynamic> data) async {
    print("DEBUG: Handling signal from: $from");

    setState(() {
      _targetIdController.text = from;
    });

    if (data.containsKey('sdp')) {
      print("DEBUG: Received SDP type: ${data['sdp']['type']}");
      RTCSessionDescription sdp = RTCSessionDescription(
        data['sdp']['sdp'],
        data['sdp']['type'],
      );

      if (sdp.type == 'offer') {
        print("DEBUG: Received Offer. Initializing Peer Connection...");

        if (_peerConnection == null) {
          _createPeerConnection();
        }

        print("DEBUG: Setting Remote Description (Offer)...");
        await _peerConnection!.setRemoteDescription(sdp);
        _remoteDescriptionSet = true;

        for (var candidate in _pendingCandidates) {
          await _peerConnection!.addCandidate(candidate);
        }
        _pendingCandidates.clear();

        print("DEBUG: Creating Answer...");
        RTCSessionDescription answer = await _peerConnection!.createAnswer();
        await _peerConnection!.setLocalDescription(answer);
        _sendSignal({'sdp': answer.toMap()});
      } else if (sdp.type == 'answer') {
        print("DEBUG: Setting Remote Description (Answer)...");
        await _peerConnection!.setRemoteDescription(sdp);
        _remoteDescriptionSet = true;

        for (var candidate in _pendingCandidates) {
          await _peerConnection!.addCandidate(candidate);
        }
        _pendingCandidates.clear();
      }
    }

    if (data.containsKey('candidate')) {
      print("DEBUG: Received ICE Candidate...");
      RTCIceCandidate candidate = RTCIceCandidate(
        data['candidate']['candidate'],
        data['candidate']['sdpMid'],
        data['candidate']['sdpMLineIndex'] as int?,
      );

      if (_remoteDescriptionSet) {
        await _peerConnection!.addCandidate(candidate);
      } else {
        _pendingCandidates.add(candidate);
      }
    }
  }

  void _setupDataChannel() {
    print("DEBUG: Setting up the data channel...");
    _dataChannelOpenedCompleter = Completer<void>();

    _dataChannel!.onMessage = (msg) {
      print("DEBUG: Data channel message received: ${msg.text}");
      setState(() {
        _messages.add("Peer: ${msg.text}");
      });
    };

    _dataChannel!.onDataChannelState = (state) {
      print("DEBUG: Data channel state changed: $state");

      if (state == RTCDataChannelState.RTCDataChannelOpen) {
        print("DEBUG: Data channel is open.");
        setState(() {
          _isDataChannelOpen = true;
        });
        _dataChannelOpenedCompleter?.complete();
      } else if (state == RTCDataChannelState.RTCDataChannelClosed) {
        print("DEBUG: Data channel is closed.");
        setState(() {
          _isDataChannelOpen = false;
        });
      }
    };
  }

  void _sendSignal(Map<String, dynamic> data) {
    if (_targetIdController.text.isNotEmpty) {
      _channel.sink.add(jsonEncode({
        'type': 'signal',
        'target': _targetIdController.text,
        'from': _clientId,
        'data': data
      }));
      print(
          "DEBUG: Sent signal with target: ${_targetIdController.text} and client ID: $_clientId");
    }
  }

  void _sendMessage() async {
    if (!_isDataChannelOpen) {
      print("DEBUG: Data channel is not open, waiting...");
      await _dataChannelOpenedCompleter?.future;
    }

    if (_messageController.text.isNotEmpty) {
      String msg = _messageController.text;
      print("DEBUG: Sending data channel message: $msg");

      if (_dataChannel != null) {
        _dataChannel!.send(RTCDataChannelMessage(msg));
        setState(() {
          _messages.add("You: $msg");
        });
        _messageController.clear();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: Text("P2P Chat ($_clientId)")),
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              TextField(
                controller: _targetIdController,
                decoration: InputDecoration(labelText: "Enter Peer ID"),
              ),
              !_peerConnected
                  ? ElevatedButton(
                      onPressed: _createPeerConnection,
                      child: Text("Connect to Peer"),
                    )
                  : Container(),
              Expanded(
                child: ListView(
                  children: _messages
                      .map((msg) => ListTile(title: Text(msg)))
                      .toList(),
                ),
              ),
              TextField(
                controller: _messageController,
                decoration: InputDecoration(labelText: "Type a message"),
              ),
              ElevatedButton(
                onPressed: _sendMessage,
                child: Text("Send Message"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
