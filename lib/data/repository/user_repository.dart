import 'package:dio/dio.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:pointycastle/asymmetric/api.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sembast/sembast.dart';
import 'package:flutter_nga/data/entity/block.dart';
import 'package:flutter_nga/data/entity/user.dart';
import 'package:flutter_nga/utils/code_utils.dart' as code_utils;
import 'package:flutter_nga/utils/nga_client_checksum.dart';

const TAG_CID = "ngaPassportCid";
const TAG_UID = "ngaPassportUid";
const TAG_USER_NAME = "ngaPassportUrlencodedUname";

/// 登录账号类型（登录表单 `type` 字段，逆向自 account_copy.html）。
/// `auto` 由服务端按账号形状自动识别（纯数字短串=用户ID、含 @=邮箱、
/// 长纯数字=手机号，其余=用户名）。
enum LoginAccountType {
  auto(''),
  mail('mail'),
  id('id'),
  phone('phone');

  const LoginAccountType(this.value);

  final String value;
}

abstract class UserRepository {
  Future<CacheUser> saveLoginCookies(String cookies);

  Future<CacheUser> saveLogin(String uid, String token, String username);

  /// 账号密码登录（原生实现，免图片验证码）。
  ///
  /// 逆向自登录 iframe（`nuke/account_copy.html` 的 `_submit`）与官方
  /// `rv.m0` 的 checksum 算法：multipart POST `/nuke.php`，密码 RSA(PKCS#1
  /// v1.5) 加密，`__ngaClientChecksum` 真值时服务端免验证码。响应
  /// `data[3]` 为 `{uid, token, username, ...}`，`token` 即会话凭据
  /// （与 WebView 流程的语义一致，直接入库当 cid 用）。
  ///
  /// 服务端偶发要求图形验证码时（错误文案含「验证码」），抛出的
  /// [DioException] 文案原样上抛——调用方据此降级到网页登录。
  Future<CacheUser> loginWithPassword({
    required String account,
    required String password,
    LoginAccountType type = LoginAccountType.auto,
  });

  Future<CacheUser?> getDefaultUser();

  Future<List<CacheUser>> getAllLoginUser();

  Future<int> quitAllLoginUser();

  Future<UserInfo> getUserInfoByName(String? username);

  Future<UserInfo> getUserInfoByUid(String? uid);

  Future<bool> setDefault(CacheUser cacheUser);

  Future<bool> deleteCacheUser(CacheUser cacheUser);

  Future<BlockInfoData> getBlockInfo();

  Future<String> setBlockInfo(BlockInfoData blockInfo);
}

class UserDataRepository implements UserRepository {
  UserDataRepository(this.database, this._dio);

  final Database database;
  final Dio _dio;

  StoreRef<int, dynamic> get _store {
    _lateInitStore ??= intMapStoreFactory.store('users');
    return _lateInitStore!;
  }

  StoreRef<int, dynamic>? _lateInitStore;

  @override
  Future<CacheUser> saveLoginCookies(String cookies) async {
    String? uid;
    String? cid;
    String? username;
    for (String c in cookies.split(";")) {
      final value = c.trim();
      debugPrint(value);
      if (value.contains(TAG_UID)) {
        uid = value.substring(TAG_UID.length + 1);
      } else if (c.contains(TAG_CID)) {
        cid = value.substring(TAG_CID.length + 1);
      } else if (c.contains(TAG_USER_NAME)) {
        username = value.substring(TAG_USER_NAME.length + 1);
        username = code_utils.urlDecode(username);
      }
    }
    if (cid != null &&
        cid.isNotEmpty &&
        uid != null &&
        uid.isNotEmpty &&
        username != null &&
        username.isNotEmpty) {
      return saveLogin(uid, cid, username);
    }
    throw "cookies parse error: cookies = $cookies";
  }

  @override
  Future<CacheUser> saveLogin(String uid, String token, String username) async {
    final user = CacheUser(uid, token, username, true);
    return saveCacheUser(user);
  }

  /// 官方登录页 RSA 公钥（account_copy.html 的 JSEncrypt setPublicKey，
  /// PKCS#1 v1.5 加密密码，2048 位）。
  static const String _rsaPublicKeyPem = '''
-----BEGIN PUBLIC KEY-----
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAyKzZWDimCN1OCprqWUhF
UPhcwxDE62/BFVP6LtQHJu+65dm4YNmDvzitmcfaXW9YbhXnd4oP7j+6vpcgJQ+p
3ucySo1ZnqO0Bb2JKEtxpCmxe7IYXhFEkJqHpFYBTiAxQz2n2mX4JZy/ehBUSMjz
gzd0NdG6Ai1C42oCzYltUOjNWZUNHn1nqpElSWHnUWqkdN8+5ISP/ZMKiQdFANkE
qDGw3/34qyF+E/hVgrGF4/CcWNP/LJCdB6DYtx7VPlQZF0tP1s+q/++rC4rQ2wmV
l2V8zGh1j7ojZbt62hVjy6byK1E/2XYo97ZtL4KDW7F5jJMvSDRFR7901UR8hCdf
4wIDAQAB
-----END PUBLIC KEY-----''';

  /// 官方 WebView 侧的 UA 标记（登录请求的 X-USER-AGENT 头用它，
  /// 服务端据此走官方客户端分支；checksum 才是免验证码的本体）
  static const String _appUserAgent =
      'Nga_Official/10001 (FlutterNGA; Android)';

  @override
  Future<CacheUser> loginWithPassword({
    required String account,
    required String password,
    LoginAccountType type = LoginAccountType.auto,
  }) async {
    // checksum 的 uid = _tempid(密码)（登录页 JS 的规则）
    final checksum = ngaClientChecksum('${ngaLoginTempId(password)}');
    final parser = encrypt.RSAKeyParser();
    final publicKey = parser.parse(_rsaPublicKeyPem) as RSAPublicKey;
    final rsaEncrypted = encrypt.Encrypter(encrypt.RSA(publicKey: publicKey))
        .encrypt(password.trim())
        .base64;

    // 与登录页 _submit 完全同构：multipart POST /nuke.php，
    // 无验证码场景不携带 rid/captcha/prid
    final formData = FormData.fromMap({
      '__lib': 'login',
      '__output': '1',
      'app_id': '1010',
      'device': '',
      'trackid': '',
      '__act': 'login',
      '__ngaClientChecksum': checksum,
      'name': account.trim(),
      'type': type.value,
      'password': rsaEncrypted,
      '__inchst': 'UTF-8',
    });
    final Response<Map<String, dynamic>> response = await _dio.post(
      'nuke.php',
      data: formData,
      options: Options(headers: {'X-USER-AGENT': _appUserAgent}),
    );

    // 拦截器已剥 script_muti_get_var_store 壳；{data:[...]} 信封整包透传
    final data = response.data!['data'];
    if (data is! List || data.length < 4) {
      throw DioException(
        requestOptions: response.requestOptions,
        error: '登录响应缺少数据字段，请稍后重试或改用网页登录',
        type: DioExceptionType.unknown,
      );
    }
    final payload = data[3];
    if (payload is! Map) {
      throw DioException(
        requestOptions: response.requestOptions,
        error: '登录响应数据格式异常，请改用网页登录',
        type: DioExceptionType.unknown,
      );
    }
    final uid = payload['uid'];
    final token = payload['token'];
    final username = payload['username'];
    if (uid == null || token == null) {
      throw DioException(
        requestOptions: response.requestOptions,
        error: '登录响应缺少凭据字段，请改用网页登录',
        type: DioExceptionType.unknown,
      );
    }
    return saveLogin(uid.toString(), token.toString(), '$username');
  }

  @override
  Future<CacheUser?> getDefaultUser() async {
    final record = await _store.findFirst(
      database,
      finder: Finder(filter: Filter.equals('enabled', true)),
    );
    if (record != null) {
      return CacheUser.fromJson(record.value);
    } else {
      return null;
    }
  }

  @override
  Future<List<CacheUser>> getAllLoginUser() async {
    final list = await _store.find(database);
    return list.map((m) => CacheUser.fromJson(m.value)).toList();
  }

  @override
  Future<int> quitAllLoginUser() {
    return _store.delete(database);
  }

  @override
  Future<UserInfo> getUserInfoByName(String? username) async {
    try {
      final encodedUsername = code_utils.urlEncode(username!);
      Response<Map<String, dynamic>> response = await _dio.get(
        "nuke.php?__lib=ucp&__act=get&__output=8&username=$encodedUsername",
      );
      // {"0": { userinfo }};
      Map<String, dynamic> userInfoMap = response.data!["0"];
      return UserInfo.fromJson(userInfoMap);
    } catch (err) {
      rethrow;
    }
  }

  @override
  Future<UserInfo> getUserInfoByUid(String? uid) async {
    try {
      Response<Map<String, dynamic>> response = await _dio.get(
        "nuke.php?__lib=ucp&__act=get&__output=8&uid=$uid",
      );
      // {"0": { userinfo }};
      Map<String, dynamic> userInfoMap = response.data!["0"];
      return UserInfo.fromJson(userInfoMap);
    } catch (err) {
      rethrow;
    }
  }

  @override
  Future<bool> setDefault(CacheUser cacheUser) async {
    final preUser = await getDefaultUser();
    if (preUser != null) {
      if (preUser.uid == cacheUser.uid) {
        return false;
      }
      await saveCacheUser(
        CacheUser(preUser.uid, preUser.cid, preUser.nickname, false),
      );
    }
    await saveCacheUser(
      CacheUser(cacheUser.uid, cacheUser.cid, cacheUser.nickname, true),
    );
    return true;
  }

  Future<CacheUser> saveCacheUser(CacheUser user) async {
    final finder = Finder(filter: Filter.equals('uid', user.uid));
    List<RecordSnapshot<int, dynamic>> list = await _store.find(
      database,
      finder: finder,
    );
    // 有以前登陆过的就把以前登陆过的删除
    if (list.isNotEmpty) {
      await _store.delete(database, finder: finder);
    }
    await _store.add(database, user.toJson());
    return user;
  }

  @override
  Future<bool> deleteCacheUser(CacheUser cacheUser) async {
    final count = await _store.delete(
      database,
      finder: Finder(filter: Filter.equals('uid', cacheUser.uid)),
    );
    final defaultUser = await getDefaultUser();
    final totalCount = await _store.count(database);
    if (defaultUser == null && totalCount > 0) {
      final record = await _store.findFirst(database);
      if (record != null) {
        final firstUser = CacheUser.fromJson(record.value);
        await saveCacheUser(
          CacheUser(firstUser.uid, firstUser.cid, firstUser.nickname, true),
        );
      }
    }
    return count > 0;
  }

  @override
  Future<BlockInfoData> getBlockInfo() async {
    try {
      final cacheUser = await getDefaultUser();
      final postData =
          "__lib=ucp&__act=get_block_word"
          "&__output=8"
          "&uid=${cacheUser?.uid}";
      final options = Options()
        ..contentType = Headers.formUrlEncodedContentType;
      options.headers = {"Referer": _dio.options.baseUrl};
      Response<Map<String, dynamic>> response = await _dio.post(
        "nuke.php",
        data: postData,
        options: options,
      );
      return BlockInfoData.fromJson(response.data!);
    } catch (err) {
      rethrow;
    }
  }

  @override
  Future<String> setBlockInfo(BlockInfoData blockInfo) async {
    try {
      final postData =
          "__lib=ucp&__act=set_block_word&__output=3&data=${code_utils.urlEncode(blockInfo.toData())}";
      final options = Options()
        ..contentType = Headers.formUrlEncodedContentType;
      options.headers = {"Referer": _dio.options.baseUrl};
      Response<Map<String, dynamic>> response = await _dio.post(
        "nuke.php",
        data: postData,
        options: options,
      );
      return response.data!["0"];
    } catch (err) {
      rethrow;
    }
  }
}
