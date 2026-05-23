import 'package:flutter/material.dart';
import '../design/components/article_player.dart';
import '../design/app_theme.dart';
import '../models/article.dart';

class PlayerScreen extends StatefulWidget {
  final UploadedArticle article;
  final List<UploadedArticle>? queue;

  const PlayerScreen({
    Key? key,
    required this.article,
    this.queue,
  }) : super(key: key);

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ArticlePlayer(
          audioUrl: widget.article.audioUrl,
          articleImageUrl: widget.article.storageUrl.isNotEmpty
              ? widget.article.storageUrl
              : null,
          articleText: widget.article.content,
          articleTitle: widget.article.title,
          onClose: () {
            Navigator.pop(context);
            if (widget.queue != null && widget.queue!.isNotEmpty) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      PlayerScreen(article: widget.queue![0], queue: widget.queue),
                ),
              );
            }
          },
        ),
      ),
    );
  }
}
