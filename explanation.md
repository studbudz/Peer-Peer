# Table of Contents
- [Introduction](#introduction)
- [Signalling.dart](#signallingdart)
- [Main.dart](#maindart)

# Introduction

This document provides a detailed explanation of the code that implements a WebRTC-based chat application. The code consists of several key components, including the `Server`, `SignalingManager`, `Conversation`, and `ChatMessage` classes, each of which plays a crucial role in managing real-time peer-to-peer communication.

There are a few terms which may be foreign. I've listed them below:
- **WebRTC**: Web Real-Time Communication, enables peer-to-peer communication.
- **RTCPeerConnection**: Represents a connection between the local device and a remote peer.
- **RTCDataChannel**: Allows the transmission of arbitrary data between peers.
- **ICE (Interactive Connectivity Establishment)**: Used to find the best path to connect peers.
- **STUN (Session Traversal Utilities for NAT)**: A protocol that allows users to discover their own IP address.
- **TURN (Traversal Using Relays around NAT)**: A protocol that relays traffic between peers when direct peer-to-peer communication is not possible.
- **SDP (Session Description Protocol)**: A format for describing the multimedia content of the connection such as codec, format information, network information, etc.
- **Completer**: A Dart class used to create and control a `Future` manually.
- **Future**: A Dart object representing a value or error that will be available at some point in the future.
- **WebSocket**: A protocol providing full-duplex communication channels over a single TCP connection.
- **WebSocketChannel**: A Dart class used to interact with WebSocket servers.
- **VoidCallback**: A Dart type alias for a function that takes no arguments and returns no value.
- **jsonEncode**: A Dart function that converts an object to a JSON string.
- **jsonDecode**: A Dart function that parses a JSON string and returns the resulting object.
- **RTCSessionDescription**: A WebRTC class that describes one end of a connection, including the media format and network information.
- **RTCIceCandidate**: A WebRTC class that represents a candidate for connection establishment.


- **`Server`**: Handles the setup of the server, receiving requests, and managing client connections. It also facilitates the initialization of WebSocket communication for signaling.
- **`SignalingManager`**: Responsible for the signaling process, including sending and receiving connection signals between peers, managing active conversations, and providing callbacks for updates.
- **`Conversation`**: Represents a chat between two peers, storing messages and handling the creation of offers and answers for WebRTC peer connections.
- **`ChatMessage`**: Defines the structure of messages exchanged during a conversation, containing properties such as text and a flag indicating whether the message was sent by the current user.

The code enables dynamic communication between users, utilizing WebRTC's peer-to-peer connection setup for a seamless real-time chat experience. The document will break down the key parts of the code, their roles, and how they contribute to the functionality of the application.

# Signalling.dart
The server acts as a stable point of connection and doesn't move. Enabling the clients to create a P2P connection to each other through the server rather than through complicated protocols.

- `generateClientId()` - generates a random string that is assigned to the client when it connects to the server.
- `handleConnection()` -
    1. Assignes clients their Id
    2. Listens to the connection and forwards messages to other connected clients
    3. Closes the connection
- `main()` -
    1. Creates the server
    2. Checks each incoming request and handles them appropriately.

> it needs to be noted that no security feature has been implemented here.
>
> I think it could be done by assigning users a token and sending the token - username combination when making server requests. The server would then check them before handling the responses.

# Main.dart
This is client/front-end section of the code. It connects to the server. Establishes a connection with client B/ handles incoming requests and then sends messages through `webRTC` (web Real Time Communication)

- `chatMessage` class stores various attributes of the message

- `Conversation` class

- `SignalingManager` class

- `P2PChatApp` class acts as the front end
    - `initState` -
        1. Initialises the `SignalingManager`
        2. Refreshes the UI after receiving it's ID
        3. triggers `SignalingManager.connect()`
    - `_connectToPeer()` - 
        1. changes the targetId
        2. starts a conversation 