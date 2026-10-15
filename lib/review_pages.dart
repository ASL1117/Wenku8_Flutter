import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_interactions.dart';
import 'app_ui.dart';
import 'catalog.dart';
import 'feature_pages.dart';
import 'legacy_transport.dart';
import 'library_state.dart';
import 'local_platform.dart';
import 'wenku_account.dart';
import 'wenku_features.dart';
import 'wenku_reviews.dart';

class BookCommunityActions extends StatelessWidget {
  const BookCommunityActions({
    super.key,
    required this.novel,
    required this.state,
    required this.repository,
  });
  final Novel novel;
  final LibraryState state;
  final NovelRepository repository;
  Future<bool> _login(BuildContext context, WenkuAccount account) async {
    if (!account.authenticated) {
      await pushNovelPage<void>(
        context,
        WenkuAccountPage(
          account: account,
          state: state,
          repository: repository,
        ),
        reduceMotion: state.reduceMotion,
      );
    }
    return context.mounted && account.authenticated;
  }

  Future<void> _mutate(
    BuildContext context,
    WenkuAccount account,
    bool recommend,
  ) async {
    if (account.busy || !await _login(context, account)) return;
    try {
      if (recommend) {
        await account.recommend(novel.id);
      } else {
        await account.addCloud(novel.id);
      }
      if (context.mounted) {
        showNovelFeedback(context, recommend ? '推荐已提交' : '已收藏到云书架');
      }
    } catch (error) {
      if (context.mounted) {
        showNovelFeedback(context, WenkuAccount.describeError(error));
      }
    }
  }

  Future<void> _share(BuildContext context) async {
    final text =
        '${novel.title}\n${novel.author}\nhttps://www.wenku8.net/book/${novel.id}.htm';
    try {
      if (LocalPlatform.mobile) {
        await LocalPlatform.shareText(text);
      } else {
        await Clipboard.setData(ClipboardData(text: text));
        if (context.mounted) showNovelFeedback(context, '图书链接已复制');
      }
    } catch (_) {
      if (context.mounted) showNovelFeedback(context, '分享未完成，请重试');
    }
  }

  @override
  Widget build(BuildContext context) {
    final features = WenkuFeaturesScope.maybeOf(context);
    if (features == null) return const SizedBox.shrink();
    return AnimatedBuilder(
      animation: features.account,
      builder: (context, _) => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          GlassTextButton(
            key: const ValueKey('detail-cloud-save'),
            onPressed: features.account.busy
                ? null
                : () => _mutate(context, features.account, false),
            child: const Text('云端收藏'),
          ),
          GlassTextButton(
            key: const ValueKey('detail-recommend'),
            onPressed: features.account.busy
                ? null
                : () => _mutate(context, features.account, true),
            child: const Text('推荐作品'),
          ),
          GlassTextButton(
            key: const ValueKey('detail-reviews'),
            onPressed: () => pushNovelPage<void>(
              context,
              WenkuReviewsPage(
                novel: novel,
                account: features.account,
                state: state,
                repository: repository,
              ),
              reduceMotion: state.reduceMotion,
            ),
            child: const Text('书评'),
          ),
          GlassTextButton(
            key: const ValueKey('detail-share'),
            onPressed: () => _share(context),
            child: const Text('分享'),
          ),
        ],
      ),
    );
  }
}

class WenkuReviewsPage extends StatefulWidget {
  const WenkuReviewsPage({
    super.key,
    required this.novel,
    required this.account,
    required this.state,
    required this.repository,
    this.thread,
    this.feed,
    this.onPosted,
  });
  final Novel novel;
  final WenkuAccount account;
  final LibraryState state;
  final NovelRepository repository;
  final WenkuReview? thread;
  final WenkuReviewFeed? feed;
  final VoidCallback? onPosted;
  @override
  State<WenkuReviewsPage> createState() => _WenkuReviewsPageState();
}

class _WenkuReviewsPageState extends State<WenkuReviewsPage> {
  late final _feed =
      widget.feed ??
      WenkuReviewFeed(
        id: widget.thread?.id ?? widget.novel.id,
        replies: widget.thread != null,
      );
  @override
  void initState() {
    super.initState();
    unawaited(_feed.load());
  }

  @override
  void dispose() {
    if (widget.feed == null) _feed.dispose();
    super.dispose();
  }

  Future<void> _compose() async {
    if (widget.account.busy) return;
    if (!widget.account.authenticated) {
      await pushNovelPage<void>(
        context,
        WenkuAccountPage(
          account: widget.account,
          state: widget.state,
          repository: widget.repository,
        ),
        reduceMotion: widget.state.reduceMotion,
      );
    }
    if (!mounted || !widget.account.authenticated) return;
    if (widget.account.profile == null) {
      try {
        await widget.account.refreshProfile();
      } catch (error) {
        if (mounted) {
          showNovelFeedback(context, WenkuAccount.describeError(error));
        }
        return;
      }
      if (!mounted) return;
    }
    final posted = await pushNovelPage<bool>(
      context,
      ReviewComposerPage(
        novel: widget.novel,
        account: widget.account,
        reduceMotion: widget.state.reduceMotion,
        thread: widget.thread,
      ),
      reduceMotion: widget.state.reduceMotion,
    );
    if (mounted && posted == true) {
      widget.onPosted?.call();
      unawaited(_feed.load(refresh: true));
    }
  }

  Future<void> _openThread(WenkuReview review) async {
    var changed = false;
    await pushNovelPage<void>(
      context,
      WenkuReviewsPage(
        novel: widget.novel,
        account: widget.account,
        state: widget.state,
        repository: widget.repository,
        thread: review,
        onPosted: () => changed = true,
      ),
      // A list and its thread share a Widget type, but are distinct routes.
      // Coalesce repeated activation per actual thread, not per Widget type.
      slot: ('review-thread', widget.novel.id, review.id),
      reduceMotion: widget.state.reduceMotion,
    );
    if (mounted && changed) unawaited(_feed.load(refresh: true));
  }

  Future<void> _loginToRead() async {
    if (widget.account.busy) return;
    await pushNovelPage<void>(
      context,
      WenkuAccountPage(
        account: widget.account,
        state: widget.state,
        repository: widget.repository,
      ),
      reduceMotion: widget.state.reduceMotion,
    );
    if (mounted && widget.account.authenticated) {
      await _feed.load(refresh: true);
    }
  }

  @override
  Widget build(BuildContext context) => ArchiveFeaturePage(
    title: widget.thread?.title ?? '作品书评',
    code: widget.thread == null
        ? 'REVIEW / ${ArchiveDesign.fileCode(widget.novel.id)}'
        : 'THREAD / ${widget.thread!.id}',
    actions: [
      GlassIconButton(
        icon: CupertinoIcons.refresh,
        label: '刷新书评',
        onPressed: () => _feed.load(refresh: true),
      ),
    ],
    child: AnimatedBuilder(
      animation: _feed,
      builder: (context, _) => _feed.requiresLogin && _feed.items.isEmpty
          ? ContentNotice(
              icon: CupertinoIcons.person_crop_circle,
              title: '登录后查看书评',
              message: '本机阅读记录和收藏不受影响。',
              actionLabel: '登录账号',
              onRetry: _loginToRead,
            )
          : LoadedContentSequence(
              generation: _feed.revision,
              firstIndex: _feed.firstIndex + 1,
              child: NotificationListener<ScrollNotification>(
                onNotification: (notification) {
                  if (notification.depth == 0 &&
                      notification.metrics.axis == Axis.vertical &&
                      notification.metrics.extentAfter < 600 &&
                      !_feed.loading &&
                      _feed.error == null &&
                      _feed.hasMore) {
                    unawaited(_feed.load());
                  }
                  return false;
                },
                child: ListView.builder(
                  padding: featurePadding(context),
                  itemCount: _feed.items.length + 2,
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            widget.thread?.title ?? widget.novel.title,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (widget.thread != null) ...[
                            const SizedBox(height: 8),
                            Text(
                              widget.novel.title,
                              style: TextStyle(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                          const SizedBox(height: 12),
                          GlassTextButton(
                            key: const ValueKey('review-compose'),
                            onPressed: _compose,
                            child: Text(
                              widget.thread == null ? '写一篇书评' : '回复这条书评',
                            ),
                          ),
                          const SizedBox(height: 20),
                          if (_feed.totalPages > 1) ...[
                            Text('已载入第 ${_feed.page} / ${_feed.totalPages} 页'),
                            const SizedBox(height: 12),
                          ],
                        ],
                      );
                    }
                    if (index == _feed.items.length + 1) {
                      return Column(
                        children: [
                          FeatureError(_feed.error),
                          if (_feed.loading)
                            SizedBox(
                              height: 100,
                              child: LoadingSkeleton(
                                layout: SkeletonLayout.bookRow,
                                label: widget.thread == null
                                    ? '正在读取书评'
                                    : '正在读取正文与回复',
                              ),
                            ),
                          if (_feed.error != null)
                            GlassTextButton(
                              onPressed: _feed.requiresLogin
                                  ? _loginToRead
                                  : () => _feed.load(),
                              child: Text(
                                _feed.requiresLogin
                                    ? '登录后继续查看'
                                    : widget.thread == null
                                    ? '重试书评'
                                    : '重试正文与回复',
                              ),
                            ),
                          if (!_feed.loading &&
                              _feed.error == null &&
                              _feed.items.isEmpty)
                            Padding(
                              padding: EdgeInsets.symmetric(vertical: 60),
                              child: Text(
                                widget.thread == null ? '还没有书评' : '暂时没有内容',
                              ),
                            ),
                          if (!_feed.loading &&
                              _feed.error == null &&
                              _feed.hasMore)
                            GlassTextButton(
                              onPressed: () => _feed.load(),
                              child: Text(
                                widget.thread == null ? '更多书评' : '更多回复',
                              ),
                            ),
                        ],
                      );
                    }
                    final review = _feed.items[index - 1];
                    return LoadedContentItem(
                      key: ValueKey(review.identity),
                      index: index,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: ContentPanel(
                          key: ValueKey('review-card-${review.identity}'),
                          onTap: widget.thread != null
                              ? null
                              : () => _openThread(review),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (widget.thread != null) ...[
                                ArchiveCode(
                                  index == 1
                                      ? '01 / ORIGINAL POST'
                                      : '${index.toString().padLeft(2, '0')} / REPLY',
                                ),
                                const SizedBox(height: 10),
                              ],
                              if (review.title.isNotEmpty) ...[
                                Text(
                                  review.title,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 10),
                              ],
                              if (review.content.isNotEmpty) ...[
                                Text(
                                  review.content,
                                  style: const TextStyle(height: 1.65),
                                ),
                                const SizedBox(height: 14),
                              ],
                              Text(
                                '${review.user}  ·  ${review.date}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                              ),
                              if (widget.thread == null) ...[
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        '${review.replies} 条回复 · 查看全文',
                                      ),
                                    ),
                                    const Icon(
                                      CupertinoIcons.chevron_right,
                                      size: 14,
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
    ),
  );
}

class ReviewComposerPage extends StatefulWidget {
  const ReviewComposerPage({
    super.key,
    required this.novel,
    required this.account,
    required this.reduceMotion,
    this.thread,
  });
  final Novel novel;
  final WenkuAccount account;
  final bool reduceMotion;
  final WenkuReview? thread;
  @override
  State<ReviewComposerPage> createState() => _ReviewComposerPageState();
}

class _ReviewComposerPageState extends State<ReviewComposerPage> {
  final _title = TextEditingController(), _body = TextEditingController();
  SharedPreferences? _preferences;
  Timer? _saveDelay;
  Future<void> _writes = Future.value();
  bool _busy = false, _loaded = false, _posted = false;
  String? _error;
  String get _key =>
      'review_draft_${widget.account.profile?.id ?? 0}_${widget.novel.id}_${widget.thread?.id ?? 0}';
  late final String _draftKey = _key;
  @override
  void initState() {
    super.initState();
    _title.addListener(_edited);
    _body.addListener(_edited);
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      _preferences = prefs;
      _title.text = prefs.getString('${_draftKey}_title') ?? '';
      _body.text = prefs.getString('${_draftKey}_body') ?? '';
    } catch (_) {
      _error = '草稿读取失败，当前编辑内容请先保留';
    }
    if (mounted) setState(() => _loaded = true);
  }

  void _edited() {
    if (!_loaded || _posted) return;
    _saveDelay?.cancel();
    _saveDelay = Timer(const Duration(milliseconds: 400), _save);
  }

  Future<void> _save() {
    _saveDelay?.cancel();
    final title = _title.text, body = _body.text, prefs = _preferences;
    if (prefs == null || _posted) return _writes;
    return _writes = _writes
        .catchError((Object _) {})
        .then((_) async {
          if (!await prefs.setString('${_draftKey}_title', title) ||
              !await prefs.setString('${_draftKey}_body', body)) {
            throw StateError('Draft write failed');
          }
        })
        .catchError((Object _) {
          if (mounted) setState(() => _error = '草稿保存失败，请保留当前内容后重试');
        });
  }

  Future<void> _post() async {
    if (_busy || !_loaded || _posted) return;
    final title = _title.text.trim(), content = _body.text.trim();
    if (content.length < 10) {
      setState(() => _error = '请填写至少 10 字的正文');
      return;
    }
    if (widget.thread == null && title.length < 2) {
      setState(() => _error = '请填写至少 2 字的标题');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    FocusManager.instance.primaryFocus?.unfocus();
    await _save();
    try {
      final encodedContent = await LegacyTransport.encodeReview(content);
      final action = widget.thread != null
          ? 'action=review&do=reply&rid=${widget.thread!.id}&content=$encodedContent'
          : 'action=review&do=post&aid=${widget.novel.id}&title=${await LegacyTransport.encodeReview(title)}&content=$encodedContent';
      await widget.account.submitReview(action);
      _posted = true;
      await _writes;
      try {
        await _preferences?.remove('${_draftKey}_title');
        await _preferences?.remove('${_draftKey}_body');
      } catch (_) {
        /* A successful server post is not retried for a draft cleanup error. */
      }
      if (mounted) {
        setState(() => _busy = false);
        Navigator.pop(context, true);
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = WenkuAccount.describeError(error);
        });
      }
    }
  }

  @override
  void dispose() {
    _saveDelay?.cancel();
    if (!_posted) unawaited(_save());
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: ArchiveFeaturePage(
      title: widget.thread == null ? '撰写书评' : '回复书评',
      code: 'REVIEW / COMPOSE',
      canPop: !_busy,
      child: ListView(
        padding: featurePadding(context),
        children: [
          Text(
            widget.thread?.title ?? widget.novel.title,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          const Text('草稿自动保存在本机，返回后可继续编辑。提交成功后清除草稿。'),
          const SizedBox(height: 20),
          if (!_loaded)
            const SizedBox(
              height: 200,
              child: LoadingSkeleton(layout: SkeletonLayout.reader),
            )
          else
            ContentPanel(
              child: Column(
                children: [
                  if (widget.thread == null)
                    TextField(
                      key: const ValueKey('review-title'),
                      controller: _title,
                      enabled: !_busy,
                      maxLength: 60,
                      decoration: const InputDecoration(labelText: '书评标题'),
                    ),
                  TextField(
                    key: const ValueKey('review-body'),
                    controller: _body,
                    enabled: !_busy,
                    minLines: 8,
                    maxLines: 20,
                    maxLength: 4000,
                    decoration: const InputDecoration(labelText: '正文'),
                  ),
                  FeatureError(_error),
                  if (_busy)
                    const SizedBox(
                      height: 64,
                      child: LoadingSkeleton(
                        layout: SkeletonLayout.actions,
                        label: '正在发表',
                      ),
                    ),
                  GlassTextButton(
                    key: const ValueKey('review-submit'),
                    onPressed: _busy || _posted ? null : _post,
                    child: Text(_posted ? '已发表' : '确认发表'),
                  ),
                ],
              ),
            ),
        ],
      ),
    ),
  );
}
