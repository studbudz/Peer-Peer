# Table of Contents
- [Introduction](#introduction)
- [Signalling.dart](#signallingdart)
- [Main.dart](#maindart)

# Introduction

This document provides a detailed explanation of the code that implements a WebRTC-based chat application. The code consists of several key components, including the `Server`, `SignalingManager`, `Conversation`, and `ChatMessage` classes, each of which plays a crucial role in managing real-time peer-to-peer communication.

- **`Server`**: Handles the setup of the server, receiving requests, and managing client connections. It also facilitates the initialization of WebSocket communication for signaling.
- **`SignalingManager`**: Responsible for the signaling process, including sending and receiving connection signals between peers, managing active conversations, and providing callbacks for updates.
- **`Conversation`**: Represents a chat between two peers, storing messages and handling the creation of offers and answers for WebRTC peer connections.
- **`ChatMessage`**: Defines the structure of messages exchanged during a conversation, containing properties such as text and a flag indicating whether the message was sent by the current user.

The code enables dynamic communication between users, utilizing WebRTC's peer-to-peer connection setup for a seamless real-time chat experience. The document will break down the key parts of the code, their roles, and how they contribute to the functionality of the application.

# Signalling.dart
The server acts as a waypoint and doesn't move. Enabling the clients to create a P2P connection to each other through the server rather than through complicated protocols.

- 


# Main.dart
Details about Main.dart.
