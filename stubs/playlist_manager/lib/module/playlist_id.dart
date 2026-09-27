class PlaylistID {
  final String id;
  const PlaylistID({required this.id});

  factory PlaylistID.fromJson(dynamic json) {
    if (json is Map) return PlaylistID(id: json['id']?.toString() ?? '');
    return PlaylistID(id: json?.toString() ?? '');
  }

  Map<String, dynamic> toJson() => {'id': id};

  @override
  bool operator ==(Object other) => other is PlaylistID && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => id;
}
