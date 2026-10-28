class ExcursionPhoto {
  const ExcursionPhoto({
    required this.id,
    required this.imageUrl,
    this.title,
    this.sortOrder = 0,
  });

  final int id;
  final String imageUrl;
  final String? title;
  final int sortOrder;

  factory ExcursionPhoto.fromJson(Map<String, dynamic> json) {
    return ExcursionPhoto(
      id: (json['id'] as num?)?.toInt() ?? 0,
      imageUrl: (json['image_url'] as String?)?.trim() ?? '',
      title: (json['title'] as String?)?.trim(),
      sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
    );
  }
}
