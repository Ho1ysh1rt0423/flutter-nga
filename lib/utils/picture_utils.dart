const _THUMB_SUFFIX = ".thumb.jpg";
const _THUMB_S_SUFFIX = ".thumb_s.jpg";
const _THUMB_SS_SUFFIX = ".thumb_ss.jpg";
const _MEDIUM_SUFFIX = ".medium.jpg";

/// 是否是原图模式
bool isOriginalUrl(String url) {
  bool originalMode = true;
  if (url.endsWith(_THUMB_SUFFIX) ||
      url.endsWith(_THUMB_S_SUFFIX) ||
      url.endsWith(_THUMB_SS_SUFFIX) ||
      url.endsWith(_MEDIUM_SUFFIX)) {
    originalMode = false;
  }
  return originalMode;
}

String getOriginalUrl(String url) {
  if (url.endsWith(_THUMB_SUFFIX)) {
    return url.substring(0, url.length - _THUMB_SUFFIX.length);
  } else if (url.endsWith(_THUMB_S_SUFFIX)) {
    return url.substring(0, url.length - _THUMB_S_SUFFIX.length);
  } else if (url.endsWith(_THUMB_SS_SUFFIX)) {
    return url.substring(0, url.length - _THUMB_SS_SUFFIX.length);
  } else if (url.endsWith(_MEDIUM_SUFFIX)) {
    return url.substring(0, url.length - _MEDIUM_SUFFIX.length);
  } else {
    return url;
  }
}

/// 列表配图用的缩略图地址。
///
/// NGA 图床支持在原图地址后直接追加 `.thumb.jpg`（原图是 jpg / webp 都适用），
/// 例如 `mon_xxx.jpg` → `mon_xxx.jpg.thumb.jpg`。已经是缩略图或带查询参数时
/// 不再重复处理，避免拼出 `.thumb.jpg.thumb.jpg`。
String getThumbUrl(String url) {
  final trimmed = url.trim();
  if (trimmed.isEmpty || !isOriginalUrl(trimmed)) return trimmed;
  if (trimmed.contains('?')) return trimmed;
  return '$trimmed$_THUMB_SUFFIX';
}
