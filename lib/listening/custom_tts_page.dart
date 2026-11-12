import 'package:flutter/material.dart';
import 'controller.dart';
import 'custom_tts.dart';

class CustomSpeechPage extends StatefulWidget {
  const CustomSpeechPage({
    super.key,
    required this.settings,
    required this.controller,
  });
  final CustomSpeechSettings settings;
  final ListeningController controller;
  @override
  State<CustomSpeechPage> createState() => _CustomSpeechPageState();
}

class _CustomSpeechPageState extends State<CustomSpeechPage> {
  late final _endpoint = TextEditingController(
    text: widget.settings.config?.endpoint,
  );
  late final _voice = TextEditingController(
    text: widget.settings.config?.voiceId ?? 'zh-CN-XiaoxiaoNeural',
  );
  late final _locale = TextEditingController(
    text: widget.settings.config?.locale ?? 'zh-CN',
  );
  late final _key = TextEditingController(
    text: widget.settings.config?.subscriptionKey,
  );
  String? _error;
  bool _busy = false;
  @override
  void dispose() {
    for (final c in [_endpoint, _voice, _locale, _key]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final config = CustomSpeechConfig(
        endpoint: _endpoint.text.trim(),
        voiceId: _voice.text.trim(),
        locale: _locale.text.trim(),
        subscriptionKey: _key.text.trim(),
      );
      await widget.settings.save(config);
      await widget.controller.setVoice(config.voice);
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is FormatException
              ? error.message.toString()
              : '保存配置或切换音源失败，请检查安全存储权限后重试',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('自定义语音接口')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          '配置 Microsoft SSML 兼容的 HTTPS 接口。朗读文本会发送至你指定的服务，密钥保存在本机安全存储中。',
        ),
        TextField(
          controller: _endpoint,
          decoration: const InputDecoration(labelText: 'HTTPS 合成地址'),
          keyboardType: TextInputType.url,
          autocorrect: false,
        ),
        TextField(
          controller: _voice,
          decoration: const InputDecoration(labelText: '音色 ID'),
          autocorrect: false,
        ),
        TextField(
          controller: _locale,
          decoration: const InputDecoration(labelText: '语言，例如 zh-CN'),
          autocorrect: false,
        ),
        TextField(
          controller: _key,
          decoration: const InputDecoration(labelText: '订阅密钥（如服务需要）'),
          obscureText: true,
          enableSuggestions: false,
          autocorrect: false,
        ),
        if (_error != null)
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: Text(_busy ? '保存中' : '保存并使用'),
        ),
      ],
    ),
  );
}
