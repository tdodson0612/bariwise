// lib/exceptions/friend_request_exception.dart
// Custom exception for friend request operations

class FriendRequestException implements Exception {
  final String message;
  final FriendRequestErrorType type;

  FriendRequestException(this.message, this.type);

  @override
  String toString() => message;
}

enum FriendRequestErrorType {
  alreadySent,
  alreadyFriends,
  alreadyReceived,
  generic,
}