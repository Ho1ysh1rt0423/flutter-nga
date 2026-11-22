import 'dart:collection';
import 'dart:convert';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:flutter_nga/data/data.dart';
import 'package:flutter_nga/data/repository/user_repository.dart';
import 'package:flutter_nga/providers/forum/favourite_forum_list_provider.dart';
import 'package:flutter_nga/ui/widget/import_cookies_dialog.dart';
import 'package:flutter_nga/utils/app_toast.dart';
import 'package:flutter_nga/utils/error_utils.dart';
import 'package:flutter_nga/utils/route.dart';

/// NGA 登录页（`nuke.php?__lib=login`）外层页面把 `body` 与登录 iframe `#iff`
/// 限宽 350px 并居中；覆盖为 100% 宽并按 App 主题着色，让表单撑满屏幕并融入
/// Material 观感。内页按自身宽度计算字号，须在 iframe 加载前生效，因此于文档
/// 开始时注入（外层与 iframe 两个分支见脚本内的 `isOuter` / `isForm`）。
/// 同时在 [_loginPagePatchScript] 完成切换前隐藏 iframe，避免闪现扫码界面。
String _loginThemeScript(ColorScheme colorScheme) {
  String cssHex(Color c) {
    String h(int v) => v.toRadixString(16).padLeft(2, '0');
    final r = (c.r * 255.0).round().clamp(0, 255);
    final g = (c.g * 255.0).round().clamp(0, 255);
    final b = (c.b * 255.0).round().clamp(0, 255);
    return '#${h(r)}${h(g)}${h(b)}';
  }

  final theme = json.encode({
    'bg': cssHex(colorScheme.surface),
    'text': cssHex(colorScheme.onSurface),
    'primary': cssHex(colorScheme.primary),
    'onPrimary': cssHex(colorScheme.onPrimary),
    'field': cssHex(colorScheme.surfaceContainerHighest),
    'border': cssHex(colorScheme.outlineVariant),
  });
  return '''
(function () {
  var isOuter = /[?&]__lib=login(&|\\\$)/.test(location.search);
  var isForm = /account_copy\\.html/.test(location.href);
  if (!isOuter && !isForm) return;
  var T = $theme;
  var css;
  if (isOuter) {
    css =
      'body, #iff { width: 100% !important; }' +
      'body { background: ' + T.bg + ' !important; }' +
      '#iff:not([data-fnga-ready]) { visibility: hidden; }';
  } else {
    css =
      'body { background: ' + T.bg + ' !important; color: ' + T.text + ' !important; }' +
      'span, div, label { color: ' + T.text + ' !important; }' +
      'input[type=text], input[type=password] { background: ' + T.field +
      ' !important; color: ' + T.text + ' !important; border: 1px solid ' + T.border +
      ' !important; border-radius: 10px !important; padding: 10px 12px !important; font-size: 15px !important; box-sizing: border-box !important; outline: none !important; }' +
      'input[type=text]:focus, input[type=password]:focus { border-color: ' + T.primary + ' !important; }' +
      'input[type=submit], input[type=button], button { background: ' + T.primary +
      ' !important; color: ' + T.onPrimary + ' !important; border: none !important; border-radius: 24px !important; padding: 10px 18px !important; font-weight: 600 !important; }' +
      'select { background: ' + T.field + ' !important; color: ' + T.text +
      ' !important; border: 1px solid ' + T.border + ' !important; border-radius: 10px !important; }' +
      'a { color: ' + T.primary + ' !important; text-decoration: none !important; }' +
      'img { border-radius: 8px !important; }';
  }
  var style = document.createElement('style');
  style.textContent = css;
  (document.head || document.documentElement).appendChild(style);
})();
''';
}

/// 官方客户端身份桥（逆向自官方 APK 的 LoginWebView / rv.m0）。
///
/// 登录 iframe（`nuke/account_copy.html`）在 `__client` 带安卓客户端位时
/// （UA 匹配 `Nga_Offic` 即置位）通过 `window.ngaObj.doAction('checksum', {uid})`
/// 索取 `__ngaClientChecksum`；浏览器环境没有这个对象，页面回落到返回空串
/// 的 `parent.__API.get`，于是表单要求输入图片验证码。官方 App 在 WebView 里
/// 注册了同名 JS 接口返回真值，因此不需要验证码。
///
/// 算法（md5 为小写 hex）：t=unix 秒，
/// `md5(md5(md5("161c8c015f912abf4434c3263279c296"+t)+"12d6af9da0f1fe4e3c87f76ce0aec149")+uid+t)+t`。
/// uid 由页面自带（`_tempid(密码)`），首登无需已知 uid。已在 node 用
/// Python hashlib 对照 14 组向量（含中文/长度边界）验证一致。
const _ngaObjShimScript = r'''
(function () {
  if (window.ngaObj) return;
  function safeAdd(x, y) {
    var lsw = (x & 0xffff) + (y & 0xffff);
    var msw = (x >> 16) + (y >> 16) + (lsw >> 16);
    return (msw << 16) | (lsw & 0xffff);
  }
  function bitRol(num, cnt) { return (num << cnt) | (num >>> (32 - cnt)); }
  function cmn(q, a, b, x, s, t) { return safeAdd(bitRol(safeAdd(safeAdd(a, q), safeAdd(x, t)), s), b); }
  function ff(a, b, c, d, x, s, t) { return cmn((b & c) | (~b & d), a, b, x, s, t); }
  function gg(a, b, c, d, x, s, t) { return cmn((b & d) | (c & ~d), a, b, x, s, t); }
  function hh(a, b, c, d, x, s, t) { return cmn(b ^ c ^ d, a, b, x, s, t); }
  function ii(a, b, c, d, x, s, t) { return cmn(c ^ (b | ~d), a, b, x, s, t); }
  function binlMd5(x, len) {
    x[len >> 5] |= 128 << (len % 32);
    x[(((len + 64) >>> 9) << 4) + 14] = len;
    var a = 1732584193, b = -271733879, c = -1732584194, d = 271733878;
    for (var i = 0; i < x.length; i += 16) {
      var oa = a, ob = b, oc = c, od = d;
      a = ff(a, b, c, d, x[i], 7, -680876936);
      d = ff(d, a, b, c, x[i+1], 12, -389564586);
      c = ff(c, d, a, b, x[i+2], 17, 606105819);
      b = ff(b, c, d, a, x[i+3], 22, -1044525330);
      a = ff(a, b, c, d, x[i+4], 7, -176418897);
      d = ff(d, a, b, c, x[i+5], 12, 1200080426);
      c = ff(c, d, a, b, x[i+6], 17, -1473231341);
      b = ff(b, c, d, a, x[i+7], 22, -45705983);
      a = ff(a, b, c, d, x[i+8], 7, 1770035416);
      d = ff(d, a, b, c, x[i+9], 12, -1958414417);
      c = ff(c, d, a, b, x[i+10], 17, -42063);
      b = ff(b, c, d, a, x[i+11], 22, -1990404162);
      a = ff(a, b, c, d, x[i+12], 7, 1804603682);
      d = ff(d, a, b, c, x[i+13], 12, -40341101);
      c = ff(c, d, a, b, x[i+14], 17, -1502002290);
      b = ff(b, c, d, a, x[i+15], 22, 1236535329);
      a = gg(a, b, c, d, x[i+1], 5, -165796510);
      d = gg(d, a, b, c, x[i+6], 9, -1069501632);
      c = gg(c, d, a, b, x[i+11], 14, 643717713);
      b = gg(b, c, d, a, x[i], 20, -373897302);
      a = gg(a, b, c, d, x[i+5], 5, -701558691);
      d = gg(d, a, b, c, x[i+10], 9, 38016083);
      c = gg(c, d, a, b, x[i+15], 14, -660478335);
      b = gg(b, c, d, a, x[i+4], 20, -405537848);
      a = gg(a, b, c, d, x[i+9], 5, 568446438);
      d = gg(d, a, b, c, x[i+14], 9, -1019803690);
      c = gg(c, d, a, b, x[i+3], 14, -187363961);
      b = gg(b, c, d, a, x[i+8], 20, 1163531501);
      a = gg(a, b, c, d, x[i+13], 5, -1444681467);
      d = gg(d, a, b, c, x[i+2], 9, -51403784);
      c = gg(c, d, a, b, x[i+7], 14, 1735328473);
      b = gg(b, c, d, a, x[i+12], 20, -1926607734);
      a = hh(a, b, c, d, x[i+5], 4, -378558);
      d = hh(d, a, b, c, x[i+8], 11, -2022574463);
      c = hh(c, d, a, b, x[i+11], 16, 1839030562);
      b = hh(b, c, d, a, x[i+14], 23, -35309556);
      a = hh(a, b, c, d, x[i+1], 4, -1530992060);
      d = hh(d, a, b, c, x[i+4], 11, 1272893353);
      c = hh(c, d, a, b, x[i+7], 16, -155497632);
      b = hh(b, c, d, a, x[i+10], 23, -1094730640);
      a = hh(a, b, c, d, x[i+13], 4, 681279174);
      d = hh(d, a, b, c, x[i], 11, -358537222);
      c = hh(c, d, a, b, x[i+3], 16, -722521979);
      b = hh(b, c, d, a, x[i+6], 23, 76029189);
      a = hh(a, b, c, d, x[i+9], 4, -640364487);
      d = hh(d, a, b, c, x[i+12], 11, -421815835);
      c = hh(c, d, a, b, x[i+15], 16, 530742520);
      b = hh(b, c, d, a, x[i+2], 23, -995338651);
      a = ii(a, b, c, d, x[i], 6, -198630844);
      d = ii(d, a, b, c, x[i+7], 10, 1126891415);
      c = ii(c, d, a, b, x[i+14], 15, -1416354905);
      b = ii(b, c, d, a, x[i+5], 21, -57434055);
      a = ii(a, b, c, d, x[i+12], 6, 1700485571);
      d = ii(d, a, b, c, x[i+3], 10, -1894986606);
      c = ii(c, d, a, b, x[i+10], 15, -1051523);
      b = ii(b, c, d, a, x[i+1], 21, -2054922799);
      a = ii(a, b, c, d, x[i+8], 6, 1873313359);
      d = ii(d, a, b, c, x[i+15], 10, -30611744);
      c = ii(c, d, a, b, x[i+6], 15, -1560198380);
      b = ii(b, c, d, a, x[i+13], 21, 1309151649);
      a = ii(a, b, c, d, x[i+4], 6, -145523070);
      d = ii(d, a, b, c, x[i+11], 10, -1120210379);
      c = ii(c, d, a, b, x[i+2], 15, 718787259);
      b = ii(b, c, d, a, x[i+9], 21, -343485551);
      a = safeAdd(a, oa); b = safeAdd(b, ob); c = safeAdd(c, oc); d = safeAdd(d, od);
    }
    return [a, b, c, d];
  }
  function binl2hex(binarray) {
    var hexTab = '0123456789abcdef';
    var str = '';
    for (var i = 0; i < binarray.length * 4; i++) {
      str += hexTab.charAt((binarray[i >> 2] >> ((i % 4) * 8 + 4)) & 15) +
             hexTab.charAt((binarray[i >> 2] >> ((i % 4) * 8)) & 15);
    }
    return str;
  }
  function md5(input) {
    // UTF-8 编码后按小端 32 位字打包（与标准 MD5 对 UTF-8 字节的定义一致）
    var bytes = [];
    for (var i = 0; i < input.length; i++) {
      var code = input.charCodeAt(i);
      if (code < 0x80) bytes.push(code);
      else if (code < 0x800) bytes.push(192 | (code >> 6), 128 | (code & 63));
      else if (code < 55296 || code >= 57344) {
        bytes.push(224 | (code >> 12), 128 | ((code >> 6) & 63), 128 | (code & 63));
      } else {
        var cp = 65536 + (((code & 1023) << 10) | (input.charCodeAt(++i) & 1023));
        bytes.push(240 | (cp >> 18), 128 | ((cp >> 12) & 63), 128 | ((cp >> 6) & 63), 128 | (cp & 63));
      }
    }
    var words = [];
    for (var j = 0; j < bytes.length * 8; j += 8) {
      words[j >> 5] = words[j >> 5] || 0;
      words[j >> 5] |= (bytes[j / 8] & 255) << (j % 32);
    }
    return binl2hex(binlMd5(words, bytes.length * 8));
  }
  function ngaChecksum(uid) {
    var t = Math.floor(Date.now() / 1000) + '';
    var md51 = md5('161c8c015f912abf4434c3263279c296' + t);
    var md52 = md5(md51 + '12d6af9da0f1fe4e3c87f76ce0aec149');
    return md5(uid + md52 + t) + t;
  }
  window.ngaObj = {
    doAction: function (name, args) {
      try {
        if (name === 'checksum') {
          var uid = '';
          try { uid = String((JSON.parse(args) || {}).uid || ''); } catch (e) {}
          return ngaChecksum(uid);
        }
        // loginSuccess：安卓模式下页面传 LoginDataBean JSON（mUID/mAccessToken/
        // mUserName），归一化成 console 管线期望的 {uid, token, username}；
        // 其余动作原样转发回外层桥（console.log → 既有 Dart 监听继续工作）
        var payload = args;
        if (name === 'loginSuccess') {
          try {
            var bean = JSON.parse(args);
            if (bean && bean.mUID !== undefined) {
              payload = JSON.stringify({
                uid: bean.mUID,
                token: bean.mAccessToken,
                username: bean.mUserName
              });
            }
          } catch (e) {}
        }
        if (window.parent && window.parent.__API && window.parent.__API.get) {
          return window.parent.__API.get(name, payload);
        }
      } catch (e) {}
      return '';
    }
  };
})();
''';

/// 调整 NGA 登录页的交互，于主框架 DOM 解析完成时注入：
///
/// - 禁止缩放。
/// - iframe（同源的 `account_copy.html`）按位掩码 `__client` 决定界面：网页环境
///   默认进入扫码登录。去掉 1024（扫码登录按钮）、加上 16384（禁用第三方登录），
///   再切到密码登录。`_qrLoginUI` 会在二维码库与 qrkey 异步加载完后再次调用自己
///   渲染扫码界面，所以先置空；扫码界面已渲染时点击其「使用密码登录」，顺带清掉
///   二维码轮询定时器。
/// - 切换完成后显示 iframe；iframe 内跳转（注册、找回密码后返回）在 `load` 时
///   重新处理。
/// - 隐藏与 AppBar 重复的「登录」标题；`<select>` 改由 `pickOption` handler 弹出
///   App 的选择对话框（网页 alert / confirm 由 `onJsAlert` / `onJsConfirm` 接管）。
const _loginPagePatchScript = r'''
(function () {
  if (!/[?&]__lib=login(&|$)/.test(location.search)) return;
  var iframe = document.getElementById('iff');
  if (!iframe || window.__fngaLoginPatch) return;
  window.__fngaLoginPatch = true;

  var viewport = document.querySelector('meta[name="viewport"]');
  if (!viewport) {
    viewport = document.createElement('meta');
    viewport.name = 'viewport';
    document.head.appendChild(viewport);
  }
  viewport.setAttribute('content',
    'width=device-width, initial-scale=1.0, maximum-scale=1.0, minimum-scale=1.0, user-scalable=no');

  function patchFrame() {
    var w = iframe.contentWindow;
    var d = w && w.document;
    if (!d || d.readyState === 'loading' || w.location.href === 'about:blank') return false;
    if (!w.__fngaPatched && typeof w._loginUI === 'function' && typeof w.__client === 'number') {
      w.__fngaPatched = true;
      enhanceSelects(d);
      var main = d.getElementById('main');
      if (main) {
        hideLoginTitle(main);
        new w.MutationObserver(function () { hideLoginTitle(main); })
          .observe(main, { childList: true });
      }
      w.__client = (w.__client | 16384) & ~1024;
      if (/^\?login(&|$)/.test(w.location.search)) {
        w._qrLoginUI = function () {};
        var toPassword = Array.prototype.find.call(
          d.querySelectorAll('#main a'),
          function (a) { return a.textContent.trim() === '使用密码登录'; }
        );
        if (toPassword) toPassword.click();
        else w._loginUI();
      }
    }
    return true;
  }

  // AppBar 已有「登录」标题，隐藏密码登录界面顶部的同名标题及其后的换行
  function hideLoginTitle(main) {
    var title = Array.prototype.find.call(
      main.querySelectorAll(':scope > div > span'),
      function (s) { return s.textContent.trim() === '登录'; }
    );
    if (!title) return;
    title.style.display = 'none';
    for (var n = title.nextElementSibling; n && n.tagName === 'BR'; n = n.nextElementSibling) {
      n.style.display = 'none';
    }
  }

  // 用 App 的选择对话框代替 <select> 的系统下拉框，选中后写回并触发 change
  function enhanceSelects(d) {
    function bridge() {
      var b = window.flutter_inappwebview;
      return b && b.callHandler ? b : null;
    }
    d.addEventListener('mousedown', function (e) {
      if (e.target.tagName === 'SELECT' && bridge()) e.preventDefault();
    }, true);
    d.addEventListener('click', function (e) {
      var select = e.target;
      var b = bridge();
      if (select.tagName !== 'SELECT' || select.disabled || !b) return;
      e.preventDefault();
      var options = Array.prototype.map.call(select.options, function (o) { return o.text; });
      var title = select.getAttribute('aria-label') || select.title || (select.id === 'type' ? '账号类型' : '');
      b.callHandler('pickOption', title, options, select.selectedIndex).then(function (index) {
        if (typeof index !== 'number' || index < 0 || index === select.selectedIndex) return;
        select.selectedIndex = index;
        select.dispatchEvent(new Event('change', { bubbles: true }));
      });
    }, true);
  }

  function reveal() {
    iframe.setAttribute('data-fnga-ready', '');
  }

  var tries = 0;
  (function poll() {
    if (patchFrame() || ++tries >= 100) return reveal();
    setTimeout(poll, 50);
  })();
  iframe.addEventListener('load', function () {
    patchFrame();
    reveal();
  });
})();
''';

/// 原生登录页：账号密码表单直连 `/nuke.php`（checksum 免验证码）。
///
/// 注册 / 找回密码 / 图形验证码等长尾流程不做原生重写，经
/// [_WebViewLoginPage]（网页版登录）承载——它已具备免验证码能力。
class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _accountController = TextEditingController();
  final _passwordController = TextEditingController();
  LoginAccountType _type = LoginAccountType.auto;
  bool _obscurePassword = true;
  bool _agreedTerms = false;
  bool _submitting = false;
  bool _captchaHint = false;

  @override
  void dispose() {
    _accountController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final account = _accountController.text.trim();
    final password = _passwordController.text;
    if (account.isEmpty) {
      AppToast.info('请输入账号');
      return;
    }
    if (password.isEmpty) {
      AppToast.info('请输入密码');
      return;
    }
    if (!_agreedTerms) {
      AppToast.info('请先阅读并同意用户协议');
      return;
    }
    setState(() => _submitting = true);
    try {
      final user = await Data().userRepository.loginWithPassword(
        account: account,
        password: password,
        type: _type,
      );
      ref.read(favouriteForumListProvider.notifier).onAccountChanged();
      if (!mounted) return;
      AppToast.success('登录成功，欢迎 ${user.nickname}');
      Routes.pop(context);
    } catch (err) {
      if (!mounted) return;
      // 服务端偶发要求图形验证码（checksum 有效性由服务端把控）：
      // 原生路径不做验证码 UI，引导网页登录兜底
      if (errorMessage(err).contains('验证码')) {
        setState(() => _captchaHint = true);
        AppToast.info('本次登录需要图形验证码，请改用网页登录');
      } else {
        AppToast.error(err);
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _openWebViewLogin() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const _WebViewLoginPage()));
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('登录'),
        actions: [
          IconButton(
            tooltip: '导入 Cookies',
            onPressed: _showImportCookiesDialog,
            icon: const Icon(Icons.cookie_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          children: [
            Text(
              '登录 NGA 玩家社区',
              style: Theme.of(context).textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _accountController,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: '账号',
                hintText: '用户名 / 邮箱 / 手机号 / 用户ID',
                prefixIcon: Icon(Icons.person_outline),
                border: OutlineInputBorder(),
              ),
              autofillHints: const [AutofillHints.username],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              decoration: InputDecoration(
                labelText: '密码',
                prefixIcon: const Icon(Icons.lock_outline),
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  tooltip: _obscurePassword ? '显示密码' : '隐藏密码',
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                ),
              ),
              autofillHints: const [AutofillHints.password],
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<LoginAccountType>(
              initialValue: _type,
              decoration: const InputDecoration(
                labelText: '账号类型',
                prefixIcon: Icon(Icons.category_outlined),
                border: OutlineInputBorder(),
              ),
              items: [
                for (final t in LoginAccountType.values)
                  DropdownMenuItem(
                    value: t,
                    child: Text(switch (t) {
                      LoginAccountType.auto => '自动识别',
                      LoginAccountType.mail => '邮箱',
                      LoginAccountType.id => '用户ID',
                      LoginAccountType.phone => '手机号',
                    }),
                  ),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _type = value);
              },
            ),
            CheckboxListTile(
              value: _agreedTerms,
              onChanged: (value) =>
                  setState(() => _agreedTerms = value ?? false),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('我已阅读并同意用户协议'),
            ),
            if (_captchaHint)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Material(
                  color: colorScheme.errorContainer.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Icon(
                          Icons.verified_user_outlined,
                          size: 18,
                          color: colorScheme.error,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '本次登录被要求图形验证码，用下方「网页登录」重试即可（已免验证码）',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _submitting ? null : _submit,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              child: _submitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('登 录'),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _submitting ? null : _openWebViewLogin,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(44),
              ),
              child: const Text('网页登录（含注册 / 找回密码）'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showImportCookiesDialog() {
    return showDialog(
      context: context,
      builder: (context) {
        return ImportCookiesDialog(cookiesCallback: _processCookiesString);
      },
    );
  }

  Future<void> _processCookiesString(String cookies) async {
    try {
      await Data().userRepository.saveLoginCookies(cookies);
      ref.read(favouriteForumListProvider.notifier).onAccountChanged();
      if (!mounted) return;
      AppToast.success('登录成功');
      Routes.pop(context);
    } catch (error, stack) {
      debugPrintStack(stackTrace: stack);
      AppToast.error(error);
    }
  }
}

class _WebViewLoginPage extends ConsumerStatefulWidget {
  const _WebViewLoginPage();

  @override
  ConsumerState<_WebViewLoginPage> createState() => _WebViewLoginPageState();
}

class _WebViewLoginPageState extends ConsumerState<_WebViewLoginPage> {
  InAppWebViewController? _webViewController;

  /// WebView 页面加载进度（0~1），AppBar 下的细进度条用
  double _progress = 0;

  @override
  Widget build(BuildContext context) {
    // 返回时先回退 WebView 历史（含 iframe 内的注册、找回密码等跳转），到底再关闭页面。
    // iframe 跳转不会触发 onUpdateVisitedHistory，因此每次返回都实时查询 canGoBack。
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _handleBack();
      },
      child: _buildScaffold(),
    );
  }

  Future<void> _handleBack() async {
    final controller = _webViewController;
    if (controller != null && await controller.canGoBack()) {
      await controller.goBack();
    } else if (mounted) {
      Navigator.of(context).pop();
    }
  }

  Widget _buildScaffold() {
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: _handleBack),
        title: Text("登录"),
        actions: <Widget>[
          IconButton(
            tooltip: "导入 Cookies",
            onPressed: _showImportCookiesDialog,
            icon: const Icon(Icons.cookie_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_progress < 1.0)
            LinearProgressIndicator(value: _progress, minHeight: 2),
          Expanded(child: _buildWebView()),
        ],
      ),
    );
  }

  Widget _buildWebView() {
    final colorScheme = Theme.of(context).colorScheme;
    return InAppWebView(
      // UA 带上官方客户端标记：登录 iframe 靠 `Nga_Offic` 置安卓客户端位，
      // 走 `ngaObj.doAction('checksum')` 桥索取 `__ngaClientChecksum`，
      // 服务端据此免图片验证码（与官方 App 的 WebView 登录同机制）。
      // 版本码用本项目自己的，页面只拿它算第三方登录按钮的显示位。
      initialSettings: InAppWebViewSettings(
        userAgent: "Nga_Official/10001 (FlutterNGA; Android)",
      ),
      initialUrlRequest: URLRequest(
        url: WebUri.uri(
          Uri.https(Data().domain, "nuke.php", {
            '__lib': 'login',
            '__act': 'account',
            'login': null,
          }),
        ),
      ),
      initialUserScripts: UnmodifiableListView([
        // 主题样式注入到所有帧：外层壳与 iframe 表单都按 App 主题着色
        UserScript(
          source: _loginThemeScript(colorScheme),
          injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
          forMainFrameOnly: false,
        ),
        // shim 必须进 iframe（登录表单在 account_copy.html 里）
        UserScript(
          source: _ngaObjShimScript,
          injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
          forMainFrameOnly: false,
        ),
        UserScript(
          source: _loginPagePatchScript,
          injectionTime: UserScriptInjectionTime.AT_DOCUMENT_END,
        ),
      ]),
      onProgressChanged: (controller, progress) {
        if (mounted) setState(() => _progress = progress / 100);
      },
      onWebViewCreated: (controller) {
        _webViewController = controller;
        controller.addJavaScriptHandler(
          handlerName: 'pickOption',
          callback: (args) => _pickOption(
            title: args[0] as String,
            options: [for (final option in args[1] as List) '$option'],
            selectedIndex: args[2] as int,
          ),
        );
      },
      onJsAlert: (controller, request) async {
        await _showWebMessage(request.message ?? '');
        return JsAlertResponse(
          handledByClient: true,
          action: JsAlertResponseAction.CONFIRM,
        );
      },
      onJsConfirm: (controller, request) async {
        final confirmed = await _showWebMessage(
          request.message ?? '',
          cancelable: true,
        );
        return JsConfirmResponse(
          handledByClient: true,
          action: confirmed
              ? JsConfirmResponseAction.CONFIRM
              : JsConfirmResponseAction.CANCEL,
        );
      },
      onConsoleMessage:
          (InAppWebViewController controller, ConsoleMessage consoleMessage) {
            if (consoleMessage.message.startsWith("loginSuccess :")) {
              final cookiesJson = consoleMessage.message.substring(
                "loginSuccess : ".length,
              );
              _processCookieJson(cookiesJson);
            }
          },
    );
  }

  Future<void> _processCookieJson(String cookiesJson) async {
    try {
      final map = json.decode(cookiesJson) as Map;
      await Data().userRepository.saveLogin(
        map['uid'].toString(),
        map['token'],
        map['username'],
      );
      ref.read(favouriteForumListProvider.notifier).onAccountChanged();
      if (mounted) {
        AppToast.success("登录成功");
        Navigator.of(context).pop();
      }
    } catch (error) {
      AppToast.error(error);
    }
  }

  /// 网页 alert / confirm；[cancelable] 为 true 时带「取消」，点外部关闭视为取消
  Future<bool> _showWebMessage(
    String message, {
    bool cancelable = false,
  }) async {
    if (!mounted) return false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('提示'),
        content: Text(message),
        actions: [
          if (cancelable)
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    return confirmed ?? !cancelable;
  }

  /// 网页 `<select>` 的选项对话框，返回选中的下标，取消时返回 null
  Future<int?> _pickOption({
    required String title,
    required List<String> options,
    required int selectedIndex,
  }) async {
    if (!mounted) return null;
    return showDialog<int>(
      context: context,
      builder: (context) {
        final colorScheme = Theme.of(context).colorScheme;
        return AlertDialog(
          title: title.isEmpty ? null : Text(title),
          content: SizedBox(
            width: double.maxFinite,
            child: RadioGroup<int>(
              groupValue: selectedIndex,
              onChanged: (index) => Navigator.of(context).pop(index),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: options.length,
                itemBuilder: (context, index) => RadioListTile<int>(
                  title: Text(options[index]),
                  value: index,
                  activeColor: colorScheme.primary,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
          ],
        );
      },
    );
  }

  void _showImportCookiesDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return ImportCookiesDialog(cookiesCallback: _processCookiesString);
      },
    );
  }

  Future<void> _processCookiesString(String cookies) async {
    try {
      await Data().userRepository.saveLoginCookies(cookies);
      ref.read(favouriteForumListProvider.notifier).onAccountChanged();
      if (!mounted) return;
      AppToast.success("登录成功");
      Navigator.of(context).pop();
    } catch (error, stack) {
      debugPrintStack(stackTrace: stack);
      AppToast.error(error);
    }
  }
}
